import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("PasskeyCredentialModel Tests")
struct PasskeyCredentialModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization produces empty model")
    func testDefaultInitialization() {
        let model = PasskeyCredentialModel()

        #expect(model.id == nil)
        #expect(model.createdAt == nil)
        #expect(model.updatedAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let modelID = UUID()
        let userID = UUID()
        let publicKey = TestFixtures.testPublicKey
        let transports: [AuthenticatorTransport] = [.internal, .hybrid, .usb]

        let model = PasskeyCredentialModel(
            id: modelID,
            userID: userID,
            credentialID: "cred-1",
            publicKey: publicKey,
            signCount: 42,
            uvInitialized: true,
            transports: transports,
            backupEligible: true,
            isBackedUp: true,
            aaguid: "aa-guid",
            attestationFormat: "apple"
        )

        #expect(model.id == modelID)
        #expect(model.$user.id == userID)
        #expect(model.credentialID == "cred-1")
        #expect(model.publicKey == publicKey)
        #expect(model.signCount == 42)
        #expect(model.uvInitialized == true)
        #expect(model.transports == transports)
        #expect(model.backupEligible == true)
        #expect(model.isBackedUp == true)
        #expect(model.aaguid == "aa-guid")
        #expect(model.attestationFormat == "apple")
    }

    @Test("Optional fields can be nil")
    func testOptionalFieldsCanBeNil() {
        let model = PasskeyCredentialModel(
            userID: UUID(),
            credentialID: "cred",
            publicKey: Data(),
            signCount: 0,
            uvInitialized: false,
            transports: [],
            backupEligible: false,
            isBackedUp: false,
            aaguid: nil,
            attestationFormat: nil
        )

        #expect(model.aaguid == nil)
        #expect(model.attestationFormat == nil)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'passkey_credentials'")
    func testSchemaName() {
        #expect(PasskeyCredentialModel.schema == "passkey_credentials")
    }

    // MARK: - Persistence Round-Trip

    @Test("Credential round-trips through SQLite with all fields intact")
    func testPersistenceRoundTrip() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("passkey-model@example.com"),
            with: nil
        )
        let userModel = try #require(user as? UserModel)

        let original = PasskeyCredentialModel.createTest(
            userID: try userModel.requireID(),
            credentialID: "cred-roundtrip",
            publicKey: TestFixtures.testPublicKey,
            signCount: 7,
            uvInitialized: true,
            transports: [.internal, .hybrid, .unknown("future-transport")],
            backupEligible: true,
            isBackedUp: false,
            aaguid: "aa",
            attestationFormat: "packed"
        )
        try await original.save(on: app.db)

        let reloaded = try #require(
            try await PasskeyCredentialModel.query(on: app.db)
                .filter(\.$credentialID == "cred-roundtrip")
                .first()
        )

        #expect(reloaded.credentialID == "cred-roundtrip")
        #expect(reloaded.publicKey == TestFixtures.testPublicKey)
        #expect(reloaded.signCount == 7)
        #expect(reloaded.uvInitialized == true)
        #expect(reloaded.transports == [.internal, .hybrid, .unknown("future-transport")])
        #expect(reloaded.backupEligible == true)
        #expect(reloaded.isBackedUp == false)
        #expect(reloaded.aaguid == "aa")
        #expect(reloaded.attestationFormat == "packed")
        #expect(reloaded.createdAt != nil)
        #expect(reloaded.updatedAt != nil)
    }

    @Test("Duplicate credentialID is rejected by unique index")
    func testCredentialIDIsUnique() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("unique@example.com"),
            with: nil
        )
        let userModel = try #require(user as? UserModel)

        let first = PasskeyCredentialModel.createTest(
            userID: try userModel.requireID(),
            credentialID: "same-id"
        )
        try await first.save(on: app.db)

        let duplicate = PasskeyCredentialModel.createTest(
            userID: try userModel.requireID(),
            credentialID: "same-id"
        )

        await #expect(throws: (any Error).self) {
            try await duplicate.save(on: app.db)
        }
    }
}
