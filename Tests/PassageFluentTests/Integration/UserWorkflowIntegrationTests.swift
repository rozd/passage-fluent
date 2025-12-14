import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

@Suite("User Workflow Integration Tests")
struct UserWorkflowIntegrationTests {

    // MARK: - Complete User Registration Flow

    @Test("Complete user registration flow with email and password")
    func testEmailRegistrationFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user with email
        let email = "newuser@example.com"
        let passwordHash = "hashedpassword123"
        let user = try await store.users.create(
            identifier: .email(email),
            with: .password(passwordHash)
        )

        #expect(user.email == email)
        #expect(user.passwordHash == passwordHash)
        #expect(user.isEmailVerified == false)
        #expect(user.isAnonymous == false)

        // 2. Find user by ID
        let foundById = try await store.users.find(byId: (user.id as? UUID)!.uuidString)
        #expect(foundById?.email == email)

        // 3. Find user by identifier
        let foundByIdentifier = try await store.users.find(byIdentifier: .email(email))
        #expect(foundByIdentifier?.email == email)
    }

    @Test("Complete user registration flow with phone")
    func testPhoneRegistrationFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user with phone
        let phone = "+1234567890"
        let passwordHash = "hashedpassword123"
        let user = try await store.users.create(
            identifier: .phone(phone),
            with: .password(passwordHash)
        )

        #expect(user.phone == phone)
        #expect(user.passwordHash == passwordHash)
        #expect(user.isPhoneVerified == false)
        #expect(user.isAnonymous == false)

        // 2. Verify phone
        try await store.users.markPhoneVerified(for: user)

        // 3. Check verification
        let foundUser = try await store.users.find(byIdentifier: .phone(phone))
        #expect(foundUser?.isPhoneVerified == true)
    }

    // MARK: - Account Linking Flow

    @Test("Link multiple identifiers to single account")
    func testAccountLinkingFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Create user with email
        let user = try await store.users.create(
            identifier: .email("user@example.com"),
            with: .password("hash")
        )

        #expect(user.email == "user@example.com")
        #expect(user.phone == nil)
        #expect(user.username == nil)

        // 2. Add phone identifier
        try await store.users.addIdentifier(.phone("+1234567890"), to: user, with: nil)

        // 3. Add username identifier
        try await store.users.addIdentifier(.username("testuser"), to: user, with: nil)

        // 4. Verify all identifiers point to same user
        let byEmail = try await store.users.find(byIdentifier: .email("user@example.com"))
        let byPhone = try await store.users.find(byIdentifier: .phone("+1234567890"))
        let byUsername = try await store.users.find(byIdentifier: .username("testuser"))

        #expect(byEmail?.id as? UUID == user.id as? UUID)
        #expect(byPhone?.id as? UUID == user.id as? UUID)
        #expect(byUsername?.id as? UUID == user.id as? UUID)

        // 5. Verify user has all identifiers
        let fullUser = try await store.users.find(byId: (user.id as? UUID)!.uuidString)
        #expect(fullUser?.email == "user@example.com")
        #expect(fullUser?.phone == "+1234567890")
        #expect(fullUser?.username == "testuser")
    }

    @Test("Convert federated user to password user")
    func testFederatedToPasswordFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Create user via federated login (no password)
        let user = try await store.users.create(
            identifier: .federated("google", userId: "google-123"),
            with: nil
        )

        #expect(user.passwordHash == nil)

        // 2. User adds email with password (converting to password-based auth)
        try await store.users.addIdentifier(
            .email("user@example.com"),
            to: user,
            with: .password("newpassword")
        )

        // 3. Verify user now has password
        let updatedUser = try await store.users.find(byIdentifier: .email("user@example.com"))
        #expect(updatedUser?.passwordHash == "newpassword")
        #expect(updatedUser?.email == "user@example.com")
    }

    // MARK: - Email Verification Flow

    @Test("Complete email verification flow")
    func testEmailVerificationFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user
        let email = "verify@example.com"
        let user = try await store.users.create(
            identifier: .email(email),
            with: nil
        )

        #expect(user.isEmailVerified == false)

        // 2. Create verification code
        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createEmailCode(
            for: user,
            email: email,
            codeHash: "verificationhash123",
            expiresAt: expiresAt
        )

        #expect(code.email == email)
        #expect(code.failedAttempts == 0)

        // 3. Find and verify code
        let foundCode = try await store.verificationCodes.findEmailCode(
            forEmail: email,
            codeHash: "verificationhash123"
        )
        #expect(foundCode != nil)

        // 4. Mark email as verified
        try await store.users.markEmailVerified(for: user)

        // 5. Invalidate used code
        try await store.verificationCodes.invalidateEmailCodes(forEmail: email)

        // 6. Verify user is now verified
        let verifiedUser = try await store.users.find(byIdentifier: .email(email))
        #expect(verifiedUser?.isEmailVerified == true)

        // 7. Verify code is invalidated
        let invalidatedCode = try await store.verificationCodes.findEmailCode(
            forEmail: email,
            codeHash: "verificationhash123"
        )
        #expect(invalidatedCode == nil)
    }

    // MARK: - Password Reset Flow

    @Test("Complete password reset flow")
    func testPasswordResetFlow() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Register user with original password
        let email = "reset@example.com"
        let user = try await store.users.create(
            identifier: .email(email),
            with: .password("originalpassword")
        )

        #expect(user.passwordHash == "originalpassword")

        // 2. Create password reset code
        let expiresAt = Date().addingTimeInterval(3600)
        let resetCode = try await store.restorationCodes.createPasswordResetCode(
            for: user,
            email: email,
            codeHash: "resetcodehash",
            expiresAt: expiresAt
        )

        #expect(resetCode.email == email)

        // 3. Find reset code
        let foundCode = try await store.restorationCodes.findPasswordResetCode(
            forEmail: email,
            codeHash: "resetcodehash"
        )
        #expect(foundCode != nil)

        // 4. Set new password
        try await store.users.setPassword(for: user, passwordHash: "newpassword")

        // 5. Invalidate used reset code
        try await store.restorationCodes.invalidatePasswordResetCodes(forEmail: email)

        // 6. Verify new password
        let updatedUser = try await store.users.find(byIdentifier: .email(email))
        #expect(updatedUser?.passwordHash == "newpassword")

        // 7. Verify code is invalidated
        let invalidatedCode = try await store.restorationCodes.findPasswordResetCode(
            forEmail: email,
            codeHash: "resetcodehash"
        )
        #expect(invalidatedCode == nil)
    }

    // MARK: - Failed Attempts Handling

    @Test("Handle failed verification attempts")
    func testFailedVerificationAttempts() async throws {
        let (app, store) = try await createTestApplicationWithStore()
        defer { Task { try? await shutdownTestApplication(app) } }

        // 1. Create user and verification code
        let email = "attempts@example.com"
        let user = try await store.users.create(
            identifier: .email(email),
            with: nil
        )

        let expiresAt = Date().addingTimeInterval(3600)
        let code = try await store.verificationCodes.createEmailCode(
            for: user,
            email: email,
            codeHash: "codehash",
            expiresAt: expiresAt
        )

        #expect(code.failedAttempts == 0)
        #expect(code.isValid(maxAttempts: 5) == true)

        // 2. Simulate failed attempts
        for i in 1...5 {
            try await store.verificationCodes.incrementFailedAttempts(for: code)

            let updatedCode = try await store.verificationCodes.findEmailCode(
                forEmail: email,
                codeHash: "codehash"
            )
            #expect(updatedCode?.failedAttempts == i)
        }

        // 3. Code should now be invalid due to max attempts
        let finalCode = try await store.verificationCodes.findEmailCode(
            forEmail: email,
            codeHash: "codehash"
        )
        #expect(finalCode?.isValid(maxAttempts: 5) == false)
    }
}
