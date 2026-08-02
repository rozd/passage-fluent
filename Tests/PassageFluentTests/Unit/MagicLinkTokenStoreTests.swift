import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.MagicLinkTokenStore Tests")
struct MagicLinkTokenStoreTests {

    // MARK: - Create Tests

    @Test("createEmailMagicLink creates a token for a user")
    func testCreateEmailMagicLinkWithUser() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let identifier = Identifier.email("test@example.com")
        let token = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: identifier,
            tokenHash: "tokenhash",
            sessionTokenHash: nil,
            expiresAt: expiresAt
        )

        #expect(token.tokenHash == "tokenhash")
        #expect(token.sessionTokenHash == nil)
        #expect(token.expiresAt == expiresAt)
        #expect(token.failedAttempts == 0)
        #expect(token.identifier == identifier)
        #expect(token.user?.email == "test@example.com")
        #expect(token.isExpired == false)
        #expect(token.isValid(maxAttempts: 5) == true)
    }

    @Test("createEmailMagicLink creates a token without a user")
    func testCreateEmailMagicLinkWithoutUser() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let expiresAt = Date().addingTimeInterval(3600)
        let identifier = Identifier.email("newuser@example.com")
        let token = try await store.magicLinkTokens.createEmailMagicLink(
            for: nil,
            identifier: identifier,
            tokenHash: "tokenhash",
            sessionTokenHash: "sessionhash",
            expiresAt: expiresAt
        )

        #expect(token.tokenHash == "tokenhash")
        #expect(token.sessionTokenHash == "sessionhash")
        #expect(token.user == nil)
        #expect(token.identifier == identifier)
    }

    // MARK: - Find Tests

    @Test("findEmailMagicLink returns nil when not found")
    func testFindEmailMagicLinkNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "nope")
        #expect(result == nil)
    }

    @Test("findEmailMagicLink returns the token when found")
    func testFindEmailMagicLinkFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        _ = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: .email("test@example.com"),
            tokenHash: "tokenhash",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        let found = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "tokenhash")
        #expect(found != nil)
        #expect(found?.tokenHash == "tokenhash")
        #expect(found?.user?.email == "test@example.com")
    }

    // MARK: - Invalidate Tests

    @Test("invalidateEmailMagicLinks invalidates active links for an identifier")
    func testInvalidateEmailMagicLinks() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        _ = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: .email("test@example.com"),
            tokenHash: "tokenhash",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        try await store.magicLinkTokens.invalidateEmailMagicLinks(for: .email("test@example.com"))

        let found = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "tokenhash")
        #expect(found == nil)
    }

    @Test("invalidateEmailMagicLinks only invalidates matching identifier")
    func testInvalidateDoesNotAffectOtherIdentifiers() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        _ = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: .email("test@example.com"),
            tokenHash: "hash-a",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )
        _ = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: .email("other@example.com"),
            tokenHash: "hash-b",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        try await store.magicLinkTokens.invalidateEmailMagicLinks(for: .email("test@example.com"))

        let invalidated = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "hash-a")
        let stillActive = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "hash-b")
        #expect(invalidated == nil)
        #expect(stillActive != nil)
    }

    // MARK: - Increment Failed Attempts Tests

    @Test("incrementFailedAttempts bumps the counter")
    func testIncrementFailedAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let token = try await store.magicLinkTokens.createEmailMagicLink(
            for: user,
            identifier: .email("test@example.com"),
            tokenHash: "tokenhash",
            sessionTokenHash: nil,
            expiresAt: Date().addingTimeInterval(3600)
        )

        #expect(token.failedAttempts == 0)

        try await store.magicLinkTokens.incrementFailedAttempts(for: token)
        try await store.magicLinkTokens.incrementFailedAttempts(for: token)

        let found = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "tokenhash")
        #expect(found?.failedAttempts == 2)
    }

    // MARK: - Initialization Test

    @Test("MagicLinkTokenStore is properly initialized")
    func testMagicLinkStoreInitialized() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let magicLinkStore = store.magicLinkTokens
        #expect(magicLinkStore is DatabaseStore.MagicLinkTokenStore<UserModel>)
    }
}
