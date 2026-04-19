import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.PasskeyCredentialStore Tests")
struct PasskeyCredentialStoreTests {

    // MARK: - Create Tests

    @Test("createPasskeyCredential persists credential with eager-loaded user")
    func testCreatePersistsCredential() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("register@example.com"),
            with: nil
        )
        let credentials = try #require(store.passkeyCredentials)

        let dto = TestFixtures.makePasskeyCredential(credentialID: "cred-create")
        let stored = try await credentials.createPasskeyCredential(for: user, from: dto)

        #expect(stored.credentialID == "cred-create")
        #expect(stored.publicKey == dto.publicKey)
        #expect(stored.signCount == dto.signCount)
        #expect(stored.uvInitialized == dto.uvInitialized)
        #expect(stored.transports == dto.transports)
        #expect(stored.backupEligible == dto.backupEligible)
        #expect(stored.isBackedUp == dto.isBackedUp)
        #expect(stored.aaguid == dto.aaguid)
        #expect(stored.attestationFormat == dto.attestationFormat)
        #expect(stored.user.email == "register@example.com")
    }

    @Test("createPasskeyCredential rejects duplicate credentialID for the same user")
    func testCreateRejectsDuplicateCredentialID() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("dupe@example.com"),
            with: nil
        )
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-dupe")
        )

        await #expect(throws: (any Error).self) {
            _ = try await credentials.createPasskeyCredential(
                for: user,
                from: TestFixtures.makePasskeyCredential(credentialID: "cred-dupe")
            )
        }
    }

    // MARK: - Find Tests

    @Test("find(byCredentialID:) returns nil when no credential exists")
    func testFindReturnsNil() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let credentials = try #require(store.passkeyCredentials)
        let result = try await credentials.find(byCredentialID: "missing")
        #expect(result == nil)
    }

    @Test("find(byCredentialID:) returns credential with eager-loaded user")
    func testFindReturnsCredential() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("find@example.com"),
            with: nil
        )
        let credentials = try #require(store.passkeyCredentials)
        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-find")
        )

        let found = try await credentials.find(byCredentialID: "cred-find")
        #expect(found != nil)
        #expect(found?.credentialID == "cred-find")
        #expect(found?.user.email == "find@example.com")
    }

    // MARK: - List Tests

    @Test("listPasskeyCredentials returns empty array when user has none")
    func testListEmpty() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("empty-list@example.com"),
            with: nil
        )
        let credentials = try #require(store.passkeyCredentials)
        let list = try await credentials.listPasskeyCredentials(forUser: user)
        #expect(list.isEmpty)
    }

    @Test("listPasskeyCredentials returns all credentials for a user")
    func testListMultiple() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("multi@example.com"),
            with: nil
        )
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-a")
        )
        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-b")
        )

        let list = try await credentials.listPasskeyCredentials(forUser: user)
        let ids = Set(list.map(\.credentialID))
        #expect(ids == ["cred-a", "cred-b"])
    }

    @Test("listPasskeyCredentials isolates credentials across users")
    func testListCrossUserIsolation() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let alice = try await store.users.create(identifier: .email("alice@example.com"), with: nil)
        let bob   = try await store.users.create(identifier: .email("bob@example.com"),   with: nil)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: alice,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-alice")
        )
        _ = try await credentials.createPasskeyCredential(
            for: bob,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-bob")
        )

        let aliceList = try await credentials.listPasskeyCredentials(forUser: alice)
        let bobList   = try await credentials.listPasskeyCredentials(forUser: bob)

        #expect(aliceList.map(\.credentialID) == ["cred-alice"])
        #expect(bobList.map(\.credentialID)   == ["cred-bob"])
    }

    // MARK: - Update After Authentication

    @Test("updatePasskeyCredentialAfterAuthentication updates signCount and backup state")
    func testUpdateSignCountAndBackup() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("update@example.com"), with: nil)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(
                credentialID: "cred-update",
                signCount: 0,
                isBackedUp: false
            )
        )

        try await credentials.updatePasskeyCredentialAfterAuthentication(
            forCredentialID: "cred-update",
            newSignCount: 123,
            isBackedUp: true
        )

        let found = try #require(try await credentials.find(byCredentialID: "cred-update"))
        #expect(found.signCount == 123)
        #expect(found.isBackedUp == true)
    }

    @Test("updatePasskeyCredentialAfterAuthentication accepts non-monotonic signCount")
    func testUpdateAllowsNonMonotonic() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("regression@example.com"), with: nil)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(
                credentialID: "cred-regression",
                signCount: 100
            )
        )

        // Sign-count monotonicity is an anti-cloning heuristic — the caller decides
        // whether to reject regressions. The store writes the value unconditionally.
        try await credentials.updatePasskeyCredentialAfterAuthentication(
            forCredentialID: "cred-regression",
            newSignCount: 50,
            isBackedUp: false
        )

        let found = try #require(try await credentials.find(byCredentialID: "cred-regression"))
        #expect(found.signCount == 50)
    }

    @Test("updatePasskeyCredentialAfterAuthentication is a no-op for missing credential")
    func testUpdateMissingCredentialNoOp() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let credentials = try #require(store.passkeyCredentials)

        // Should not throw.
        try await credentials.updatePasskeyCredentialAfterAuthentication(
            forCredentialID: "never-registered",
            newSignCount: 1,
            isBackedUp: false
        )
    }

    // MARK: - Delete Tests

    @Test("deletePasskeyCredential removes the row")
    func testDeleteRemovesRow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("delete@example.com"), with: nil)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-delete")
        )

        try await credentials.deletePasskeyCredential(byCredentialID: "cred-delete")

        let afterDelete = try await credentials.find(byCredentialID: "cred-delete")
        #expect(afterDelete == nil)
    }

    @Test("deletePasskeyCredential is a no-op for missing credential")
    func testDeleteMissingNoOp() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let credentials = try #require(store.passkeyCredentials)
        try await credentials.deletePasskeyCredential(byCredentialID: "never-existed")
    }

    @Test("Deleting one credential leaves others for the same user intact")
    func testDeleteIsolatedToCredentialID() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("multi-delete@example.com"), with: nil)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "keep")
        )
        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "drop")
        )

        try await credentials.deletePasskeyCredential(byCredentialID: "drop")

        let list = try await credentials.listPasskeyCredentials(forUser: user)
        #expect(list.map(\.credentialID) == ["keep"])
    }

    // MARK: - Cascade Delete

    @Test("Deleting user cascades to their passkey credentials")
    func testUserDeletionCascades() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("cascade@example.com"), with: nil)
        let userModel = try #require(user as? UserModel)
        let credentials = try #require(store.passkeyCredentials)

        _ = try await credentials.createPasskeyCredential(
            for: user,
            from: TestFixtures.makePasskeyCredential(credentialID: "cred-cascade")
        )

        try await userModel.delete(on: app.db)

        let afterCascade = try await credentials.find(byCredentialID: "cred-cascade")
        #expect(afterCascade == nil)
    }
}
