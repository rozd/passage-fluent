import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("DatabaseStore.VerificationCodeStore Tests")
struct VerificationCodeStoreTests {

    // MARK: - Email Code Tests

    @Test("createEmailCode creates email verification code")
    func testCreateEmailCode() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        #expect(code.email == "test@example.com")
        #expect(code.codeHash == "codehash123")
        #expect(code.failedAttempts == 0)
    }

    @Test("findEmailCode returns nil when not found")
    func testFindEmailCodeNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.verificationCodes.findEmailCode(
            forEmail: "nonexistent@example.com",
            codeHash: "hash"
        )
        #expect(result == nil)
    }

    @Test("findEmailCode returns code when found")
    func testFindEmailCodeFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        let result = try await store.verificationCodes.findEmailCode(
            forEmail: "test@example.com",
            codeHash: "codehash123"
        )

        #expect(result != nil)
        #expect(result?.email == "test@example.com")
        #expect(result?.codeHash == "codehash123")
        #expect(result?.user.email == "test@example.com")
    }

    @Test("findEmailCode returns nil for invalidated codes")
    func testFindEmailCodeInvalidated() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        // Invalidate codes
        try await store.verificationCodes.invalidateEmailCodes(forEmail: "test@example.com")

        // Should not find invalidated code
        let result = try await store.verificationCodes.findEmailCode(
            forEmail: "test@example.com",
            codeHash: "codehash123"
        )
        #expect(result == nil)
    }

    @Test("invalidateEmailCodes invalidates all codes for email")
    func testInvalidateEmailCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and multiple codes
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "hash1",
            expiresAt: expiresAt
        )
        _ = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "hash2",
            expiresAt: expiresAt
        )

        // Invalidate all codes
        try await store.verificationCodes.invalidateEmailCodes(forEmail: "test@example.com")

        // Neither code should be found
        let result1 = try await store.verificationCodes.findEmailCode(
            forEmail: "test@example.com",
            codeHash: "hash1"
        )
        let result2 = try await store.verificationCodes.findEmailCode(
            forEmail: "test@example.com",
            codeHash: "hash2"
        )

        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("incrementFailedAttempts for email code increments counter")
    func testIncrementEmailCodeFailedAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .email("test@example.com"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createEmailCode(
            for: user,
            email: "test@example.com",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        #expect(code.failedAttempts == 0)

        // Increment failed attempts
        try await store.verificationCodes.incrementFailedAttempts(for: code)

        // Verify increment
        let updatedCode = try await store.verificationCodes.findEmailCode(
            forEmail: "test@example.com",
            codeHash: "codehash123"
        )
        #expect(updatedCode?.failedAttempts == 1)
    }

    // MARK: - Phone Code Tests

    @Test("createPhoneCode creates phone verification code")
    func testCreatePhoneCode() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        #expect(code.phone == "+1234567890")
        #expect(code.codeHash == "codehash123")
        #expect(code.failedAttempts == 0)
    }

    @Test("findPhoneCode returns nil when not found")
    func testFindPhoneCodeNotFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        let result = try await store.verificationCodes.findPhoneCode(
            forPhone: "+0000000000",
            codeHash: "hash"
        )
        #expect(result == nil)
    }

    @Test("findPhoneCode returns code when found")
    func testFindPhoneCodeFound() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        let result = try await store.verificationCodes.findPhoneCode(
            forPhone: "+1234567890",
            codeHash: "codehash123"
        )

        #expect(result != nil)
        #expect(result?.phone == "+1234567890")
        #expect(result?.codeHash == "codehash123")
        #expect(result?.user.phone == "+1234567890")
    }

    @Test("findPhoneCode returns nil for invalidated codes")
    func testFindPhoneCodeInvalidated() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        // Invalidate codes
        try await store.verificationCodes.invalidatePhoneCodes(forPhone: "+1234567890")

        // Should not find invalidated code
        let result = try await store.verificationCodes.findPhoneCode(
            forPhone: "+1234567890",
            codeHash: "codehash123"
        )
        #expect(result == nil)
    }

    @Test("invalidatePhoneCodes invalidates all codes for phone")
    func testInvalidatePhoneCodes() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and multiple codes
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        _ = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "hash1",
            expiresAt: expiresAt
        )
        _ = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "hash2",
            expiresAt: expiresAt
        )

        // Invalidate all codes
        try await store.verificationCodes.invalidatePhoneCodes(forPhone: "+1234567890")

        // Neither code should be found
        let result1 = try await store.verificationCodes.findPhoneCode(
            forPhone: "+1234567890",
            codeHash: "hash1"
        )
        let result2 = try await store.verificationCodes.findPhoneCode(
            forPhone: "+1234567890",
            codeHash: "hash2"
        )

        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("incrementFailedAttempts for phone code increments counter")
    func testIncrementPhoneCodeFailedAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // Create user and code
        let user = try await store.users.create(
            identifier: .phone("+1234567890"),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createPhoneCode(
            for: user,
            phone: "+1234567890",
            codeHash: "codehash123",
            expiresAt: expiresAt
        )

        #expect(code.failedAttempts == 0)

        // Increment failed attempts
        try await store.verificationCodes.incrementFailedAttempts(for: code)

        // Verify increment
        let updatedCode = try await store.verificationCodes.findPhoneCode(
            forPhone: "+1234567890",
            codeHash: "codehash123"
        )
        #expect(updatedCode?.failedAttempts == 1)
    }
}
