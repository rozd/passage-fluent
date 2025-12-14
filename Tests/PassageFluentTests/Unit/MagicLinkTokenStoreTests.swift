import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.MagicLinkTokenStore Tests")
struct MagicLinkTokenStoreTests {

    // MARK: - Not Implemented Tests

    @Test("createEmailMagicLink throws not implemented error")
    func testCreateEmailMagicLinkNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let identifier = Identifier.email("test@example.com")

        await #expect(throws: PassageError.self) {
            _ = try await store.magicLinkTokens.createEmailMagicLink(
                for: user,
                identifier: identifier,
                tokenHash: "tokenhash",
                sessionTokenHash: nil,
                expiresAt: expiresAt
            )
        }
    }

    @Test("createEmailMagicLink throws not implemented error without user")
    func testCreateEmailMagicLinkWithoutUserNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let expiresAt = Date().addingTimeInterval(3600)
        let identifier = Identifier.email("test@example.com")

        await #expect(throws: PassageError.self) {
            _ = try await store.magicLinkTokens.createEmailMagicLink(
                for: nil,
                identifier: identifier,
                tokenHash: "tokenhash",
                sessionTokenHash: "sessionhash",
                expiresAt: expiresAt
            )
        }
    }

    @Test("findEmailMagicLink throws not implemented error")
    func testFindEmailMagicLinkNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        await #expect(throws: PassageError.self) {
            _ = try await store.magicLinkTokens.findEmailMagicLink(tokenHash: "tokenhash")
        }
    }

    @Test("invalidateEmailMagicLinks throws not implemented error")
    func testInvalidateEmailMagicLinksNotImplemented() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let identifier = Identifier.email("test@example.com")

        await #expect(throws: PassageError.self) {
            try await store.magicLinkTokens.invalidateEmailMagicLinks(for: identifier)
        }
    }

    @Test("MagicLinkTokenStore is properly initialized")
    func testMagicLinkStoreInitialized() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Test that the store type exists and is properly initialized
        let magicLinkStore = store.magicLinkTokens
        #expect(magicLinkStore is DatabaseStore.MagicLinkTokenStore)
    }
}
