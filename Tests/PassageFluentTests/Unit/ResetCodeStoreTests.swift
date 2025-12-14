import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.ResetCodeStore Tests")
struct ResetCodeStoreTests {

    // MARK: - Email Reset Code Tests

    @Test("createPasswordResetCode for email creates reset code")
    func testCreateEmailResetCode() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        #expect(code.email == "test@example.com")
        #expect(code.codeHash == "resetcodehash123")
        #expect(code.failedAttempts == 0)
    }

    @Test("findPasswordResetCode for email returns nil when not found")
    func testFindEmailResetCodeNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "nonexistent@example.com",
            codeHash: "hash"
        )
        #expect(result == nil)
    }

    @Test("findPasswordResetCode for email returns code when found")
    func testFindEmailResetCodeFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        let result = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "test@example.com",
            codeHash: "resetcodehash123"
        )

        #expect(result != nil)
        #expect(result?.email == "test@example.com")
        #expect(result?.codeHash == "resetcodehash123")
        #expect(result?.user.email == "test@example.com")
    }

    @Test("findPasswordResetCode for email returns nil for invalidated codes")
    func testFindEmailResetCodeInvalidated() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        // Invalidate codes
        try await store.restorationCodes.invalidatePasswordResetCodes(forEmail: "test@example.com")

        // Should not find invalidated code
        let result = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "test@example.com",
            codeHash: "resetcodehash123"
        )
        #expect(result == nil)
    }

    @Test("invalidatePasswordResetCodes for email invalidates all codes")
    func testInvalidateEmailResetCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and multiple codes
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "hash1",
            expiresAt: expiresAt
        )
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "hash2",
            expiresAt: expiresAt
        )

        // Invalidate all codes
        try await store.restorationCodes.invalidatePasswordResetCodes(forEmail: "test@example.com")

        // Neither code should be found
        let result1 = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "test@example.com",
            codeHash: "hash1"
        )
        let result2 = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "test@example.com",
            codeHash: "hash2"
        )

        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("incrementFailedAttempts for email reset code increments counter")
    func testIncrementEmailResetCodeFailedAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: "test@example.com",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        #expect(code.failedAttempts == 0)

        // Increment failed attempts
        try await store.restorationCodes.incrementFailedAttempts(for: code)

        // Verify increment
        let updatedCode = try await store.restorationCodes.findPasswordResetCode(
            forEmail: "test@example.com",
            codeHash: "resetcodehash123"
        )
        #expect(updatedCode?.failedAttempts == 1)
    }

    // MARK: - Phone Reset Code Tests

    @Test("createPasswordResetCode for phone creates reset code")
    func testCreatePhoneResetCode() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        #expect(code.phone == "+1234567890")
        #expect(code.codeHash == "resetcodehash123")
        #expect(code.failedAttempts == 0)
    }

    @Test("findPasswordResetCode for phone returns nil when not found")
    func testFindPhoneResetCodeNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+0000000000",
            codeHash: "hash"
        )
        #expect(result == nil)
    }

    @Test("findPasswordResetCode for phone returns code when found")
    func testFindPhoneResetCodeFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        let result = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+1234567890",
            codeHash: "resetcodehash123"
        )

        #expect(result != nil)
        #expect(result?.phone == "+1234567890")
        #expect(result?.codeHash == "resetcodehash123")
        #expect(result?.user.phone == "+1234567890")
    }

    @Test("findPasswordResetCode for phone returns nil for invalidated codes")
    func testFindPhoneResetCodeInvalidated() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        // Invalidate codes
        try await store.restorationCodes.invalidatePasswordResetCodes(forPhone: "+1234567890")

        // Should not find invalidated code
        let result = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+1234567890",
            codeHash: "resetcodehash123"
        )
        #expect(result == nil)
    }

    @Test("invalidatePasswordResetCodes for phone invalidates all codes")
    func testInvalidatePhoneResetCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and multiple codes
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "hash1",
            expiresAt: expiresAt
        )
        _ = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "hash2",
            expiresAt: expiresAt
        )

        // Invalidate all codes
        try await store.restorationCodes.invalidatePasswordResetCodes(forPhone: "+1234567890")

        // Neither code should be found
        let result1 = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+1234567890",
            codeHash: "hash1"
        )
        let result2 = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+1234567890",
            codeHash: "hash2"
        )

        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("incrementFailedAttempts for phone reset code increments counter")
    func testIncrementPhoneResetCodeFailedAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            phone: "+1234567890",
            codeHash: "resetcodehash123",
            expiresAt: expiresAt
        )

        #expect(code.failedAttempts == 0)

        // Increment failed attempts
        try await store.restorationCodes.incrementFailedAttempts(for: code)

        // Verify increment
        let updatedCode = try await store.restorationCodes.findPasswordResetCode(
            forPhone: "+1234567890",
            codeHash: "resetcodehash123"
        )
        #expect(updatedCode?.failedAttempts == 1)
    }
}
