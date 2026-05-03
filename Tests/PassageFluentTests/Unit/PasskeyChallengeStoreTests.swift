import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.PasskeyChallengeStore Tests")
struct PasskeyChallengeStoreTests {

    // MARK: - Create (for: User) Tests

    @Test("createPasskeyChallenge(for: User) persists hash and binds the user")
    func testCreateForUserPersistsHashedChallenge() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("challenge@example.com"), with: nil)
        let challenges = try #require(store.passkeyChallenges)

        let bytes = TestFixtures.testChallengeBytes
        let expected = bytes.sha256Hex

        let stored = try await challenges.createPasskeyChallenge(
            for: user,
            from: TestFixtures.makePasskeyChallenge(bytes: bytes, kind: .registration)
        )

        #expect(stored.challengeHash == expected)
        #expect(stored.kind == .registration)
        #expect(stored.user?.email == "challenge@example.com")
        #expect(stored.identifier == nil)
        #expect(stored.isConsumed == false)
        #expect(stored.isExpired == false)
    }

    // MARK: - Create (from:) Tests — discoverable authentication

    @Test("createPasskeyChallenge(from:) persists with no user and no identifier")
    func testCreateFromForDiscoverableAuth() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        let stored = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(
                bytes: Data([0x01, 0x02, 0x03]),
                kind: .authentication
            )
        )

        #expect(stored.user == nil)
        #expect(stored.identifier == nil)
        #expect(stored.kind == .authentication)
    }

    // MARK: - Create (for: Identifier) Tests — guest registration

    @Test("createPasskeyChallenge(for: Identifier) persists identifier without binding a user")
    func testCreateForIdentifierGuestRegistration() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)
        let identifier = Identifier.email("guest@example.com")

        let stored = try await challenges.createPasskeyChallenge(
            for: identifier,
            from: TestFixtures.makePasskeyChallenge(
                bytes: Data([0x10, 0x11, 0x12]),
                kind: .registration
            )
        )

        #expect(stored.user == nil)
        #expect(stored.identifier == identifier)
        #expect(stored.kind == .registration)
    }

    @Test("createPasskeyChallenge(for: Identifier) round-trips identifier through the database")
    func testCreateForIdentifierRoundTrip() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)
        let bytes = Data([0x20, 0x21, 0x22])
        let identifier = Identifier.username("guest-user")

        _ = try await challenges.createPasskeyChallenge(
            for: identifier,
            from: TestFixtures.makePasskeyChallenge(bytes: bytes, kind: .registration)
        )

        let reloaded = try #require(try await challenges.find(passkeyChallengeMatching: bytes))
        #expect(reloaded.identifier == identifier)
        #expect(reloaded.user == nil)
    }

    @Test("createPasskeyChallenge rejects duplicate raw bytes (unique hash)")
    func testCreateRejectsDuplicateBytes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(bytes: Data([0x42, 0x42]))
        )

        await #expect(throws: (any Error).self) {
            _ = try await challenges.createPasskeyChallenge(
                from: TestFixtures.makePasskeyChallenge(bytes: Data([0x42, 0x42]))
            )
        }
    }

    // MARK: - Find Tests

    @Test("find(passkeyChallengeMatching:) hashes bytes internally to locate row")
    func testFindByBytes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("find-c@example.com"), with: nil)
        let challenges = try #require(store.passkeyChallenges)

        let bytes = Data([0xAA, 0xBB, 0xCC, 0xDD])
        _ = try await challenges.createPasskeyChallenge(
            for: user,
            from: TestFixtures.makePasskeyChallenge(bytes: bytes, kind: .registration)
        )

        let found = try await challenges.find(passkeyChallengeMatching: bytes)
        #expect(found != nil)
        #expect(found?.challengeHash == bytes.sha256Hex)
        #expect(found?.user?.email == "find-c@example.com")
    }

    @Test("find(passkeyChallengeMatching:) returns nil for unknown bytes")
    func testFindReturnsNil() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)
        let found = try await challenges.find(passkeyChallengeMatching: Data([0xFF]))
        #expect(found == nil)
    }

    @Test("find(passkeyChallengeMatching:) does not leak across challenges")
    func testFindIsolation() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        let aBytes = Data([0x01, 0x02])
        let bBytes = Data([0x03, 0x04])

        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(bytes: aBytes, kind: .registration)
        )
        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(bytes: bBytes, kind: .authentication)
        )

        let foundA = try #require(try await challenges.find(passkeyChallengeMatching: aBytes))
        let foundB = try #require(try await challenges.find(passkeyChallengeMatching: bBytes))

        #expect(foundA.kind == .registration)
        #expect(foundB.kind == .authentication)
        #expect(foundA.challengeHash != foundB.challengeHash)
    }

    // MARK: - Consume Tests

    @Test("consume marks challenge as consumed and invalidates it")
    func testConsume() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        let bytes = Data([0x99])
        let stored = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(bytes: bytes)
        )
        #expect(stored.isValid == true)

        try await challenges.consume(passkeyChallenge: stored)

        let reloaded = try #require(try await challenges.find(passkeyChallengeMatching: bytes))
        #expect(reloaded.isConsumed == true)
        #expect(reloaded.isValid == false)
    }

    @Test("Consuming an already-consumed challenge keeps it consumed")
    func testConsumeIdempotent() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        let bytes = Data([0x77, 0x77])
        let stored = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(bytes: bytes)
        )

        try await challenges.consume(passkeyChallenge: stored)
        try await challenges.consume(passkeyChallenge: stored)

        let reloaded = try #require(try await challenges.find(passkeyChallengeMatching: bytes))
        #expect(reloaded.isConsumed == true)
    }

    // MARK: - Cleanup Tests

    @Test("cleanupExpiredPasskeyChallenges deletes only expired rows")
    func testCleanupExpired() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        let expiredBytes = Data([0x00, 0x01])
        let freshBytes   = Data([0x02, 0x03])

        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(
                bytes: expiredBytes,
                expiresAt: Date().addingTimeInterval(-60)
            )
        )
        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(
                bytes: freshBytes,
                expiresAt: Date().addingTimeInterval(60)
            )
        )

        try await challenges.cleanupExpiredPasskeyChallenges(before: Date())

        let expired = try await challenges.find(passkeyChallengeMatching: expiredBytes)
        let fresh   = try await challenges.find(passkeyChallengeMatching: freshBytes)

        #expect(expired == nil)
        #expect(fresh != nil)
    }

    @Test("cleanupExpiredPasskeyChallenges is safe when nothing to delete")
    func testCleanupNoOp() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)

        _ = try await challenges.createPasskeyChallenge(
            from: TestFixtures.makePasskeyChallenge(
                bytes: Data([0x10, 0x20]),
                expiresAt: Date().addingTimeInterval(3600)
            )
        )

        try await challenges.cleanupExpiredPasskeyChallenges(before: Date())

        let found = try await challenges.find(passkeyChallengeMatching: Data([0x10, 0x20]))
        #expect(found != nil)
    }

    // MARK: - Cascade Delete

    @Test("Deleting user cascades to their (user-bound) challenges")
    func testUserDeletionCascadesToChallenges() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(identifier: .email("cascade-c@example.com"), with: nil)
        let userModel = try #require(user as? UserModel)
        let challenges = try #require(store.passkeyChallenges)

        let bytes = Data([0xCA, 0xFE])
        _ = try await challenges.createPasskeyChallenge(
            for: user,
            from: TestFixtures.makePasskeyChallenge(bytes: bytes)
        )

        try await userModel.delete(on: app.db)

        let afterCascade = try await challenges.find(passkeyChallengeMatching: bytes)
        #expect(afterCascade == nil)
    }

    @Test("Identifier-bound challenges survive when no user exists yet")
    func testIdentifierBoundChallengesAreIndependentOfUser() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let challenges = try #require(store.passkeyChallenges)
        let bytes = Data([0xBE, 0xEF])
        let identifier = Identifier.email("not-yet@example.com")

        _ = try await challenges.createPasskeyChallenge(
            for: identifier,
            from: TestFixtures.makePasskeyChallenge(bytes: bytes, kind: .registration)
        )

        let reloaded = try #require(try await challenges.find(passkeyChallengeMatching: bytes))
        #expect(reloaded.user == nil)
        #expect(reloaded.identifier == identifier)
    }
}
