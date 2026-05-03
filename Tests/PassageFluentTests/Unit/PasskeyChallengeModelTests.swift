import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("PasskeyChallengeModel Tests")
struct PasskeyChallengeModelTests {

    // MARK: - Initialization Tests

    @Test("Default initialization produces empty model")
    func testDefaultInitialization() {
        let model = PasskeyChallengeModel()

        #expect(model.id == nil)
        #expect(model.consumedAt == nil)
        #expect(model.createdAt == nil)
    }

    @Test("Full initialization sets all provided values")
    func testFullInitialization() {
        let modelID = UUID()
        let userID = UUID()
        let consumedAt = Date()
        let expiresAt = Date().addingTimeInterval(60)
        let identifier = Identifier.email("init@example.com")

        let model = PasskeyChallengeModel(
            id: modelID,
            identifier: identifier,
            userID: userID,
            kind: .authentication,
            challengeHash: "abc123",
            expiresAt: expiresAt,
            consumedAt: consumedAt
        )

        #expect(model.id == modelID)
        #expect(model.identifier == identifier)
        #expect(model.$user.id == userID)
        #expect(model.kindRaw == "authentication")
        #expect(model.kind == .authentication)
        #expect(model.challengeHash == "abc123")
        #expect(model.expiresAt == expiresAt)
        #expect(model.consumedAt == consumedAt)
    }

    @Test("Initialization with nil userID is supported for discoverable auth")
    func testInitWithNilUser() {
        let model = PasskeyChallengeModel(
            userID: nil,
            kind: .authentication,
            challengeHash: "hash",
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(model.$user.id == nil)
        #expect(model.identifier == nil)
    }

    @Test("Initialization with identifier and nil userID is supported for guest registration")
    func testInitWithIdentifierAndNoUser() {
        let identifier = Identifier.email("guest@example.com")
        let model = PasskeyChallengeModel(
            identifier: identifier,
            userID: nil,
            kind: .registration,
            challengeHash: "hash",
            expiresAt: Date().addingTimeInterval(60)
        )

        #expect(model.identifier == identifier)
        #expect(model.$user.id == nil)
    }

    // MARK: - Schema Tests

    @Test("Schema name is 'passkey_challenges'")
    func testSchemaName() {
        #expect(PasskeyChallengeModel.schema == "passkey_challenges")
    }

    // MARK: - Kind Getter

    @Test("kind getter decodes registration raw value")
    func testKindRegistration() {
        let model = PasskeyChallengeModel.createTest(kind: .registration)
        #expect(model.kind == .registration)
        #expect(model.kindRaw == "registration")
    }

    @Test("kind getter decodes authentication raw value")
    func testKindAuthentication() {
        let model = PasskeyChallengeModel.createTest(kind: .authentication)
        #expect(model.kind == .authentication)
        #expect(model.kindRaw == "authentication")
    }

    @Test("kind getter falls back to authentication for unknown raw values")
    func testKindFallback() {
        // Simulate a corrupted DB row written by a future version.
        let model = PasskeyChallengeModel.createTest()
        model.kindRaw = "some-future-kind"
        #expect(model.kind == .authentication)
    }

    // MARK: - Validation Helpers

    @Test("isExpired is false for future expiration")
    func testIsExpiredFuture() {
        let model = PasskeyChallengeModel.createTest(
            expiresAt: Date().addingTimeInterval(60)
        )
        #expect(model.isExpired == false)
    }

    @Test("isExpired is true for past expiration")
    func testIsExpiredPast() {
        let model = PasskeyChallengeModel.createTest(
            expiresAt: Date().addingTimeInterval(-60)
        )
        #expect(model.isExpired == true)
    }

    @Test("isConsumed is false when consumedAt is nil")
    func testIsConsumedFalse() {
        let model = PasskeyChallengeModel.createTest(consumedAt: nil)
        #expect(model.isConsumed == false)
    }

    @Test("isConsumed is true when consumedAt is set")
    func testIsConsumedTrue() {
        let model = PasskeyChallengeModel.createTest(consumedAt: Date())
        #expect(model.isConsumed == true)
    }

    @Test("isValid is true when not expired and not consumed")
    func testIsValidTrue() {
        let model = PasskeyChallengeModel.createTest(
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: nil
        )
        #expect(model.isValid == true)
    }

    @Test("isValid is false when expired")
    func testIsValidFalseExpired() {
        let model = PasskeyChallengeModel.createTest(
            expiresAt: Date().addingTimeInterval(-60),
            consumedAt: nil
        )
        #expect(model.isValid == false)
    }

    @Test("isValid is false when consumed")
    func testIsValidFalseConsumed() {
        let model = PasskeyChallengeModel.createTest(
            expiresAt: Date().addingTimeInterval(60),
            consumedAt: Date()
        )
        #expect(model.isValid == false)
    }

    // MARK: - Persistence Round-Trip

    @Test("Challenge persists and reloads with nil user for discoverable auth")
    func testRoundTripNilUser() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let original = PasskeyChallengeModel.createTest(
            userID: nil,
            kind: .authentication,
            challengeHash: "hash-discoverable"
        )
        try await original.save(on: app.db)

        let reloaded = try #require(
            try await PasskeyChallengeModel.query(on: app.db)
                .filter(\.$challengeHash == "hash-discoverable")
                .first()
        )

        #expect(reloaded.$user.id == nil)
        #expect(reloaded.kind == .authentication)
        #expect(reloaded.createdAt != nil)
    }

    @Test("Duplicate challengeHash is rejected by unique index")
    func testChallengeHashIsUnique() async throws {
        let (app, _) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let first = PasskeyChallengeModel.createTest(
            userID: nil,
            challengeHash: "same-hash"
        )
        try await first.save(on: app.db)

        let duplicate = PasskeyChallengeModel.createTest(
            userID: nil,
            challengeHash: "same-hash"
        )

        await #expect(throws: (any Error).self) {
            try await duplicate.save(on: app.db)
        }
    }
}
