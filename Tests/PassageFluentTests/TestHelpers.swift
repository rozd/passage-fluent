import Foundation
import Testing
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

// MARK: - Test Application Setup

/// Creates a test application with in-memory SQLite database
func createTestApplication() async throws -> Application {
    let app = try await Application.make(.testing)

    // Configure in-memory SQLite database
    app.databases.use(.sqlite(.memory), as: .sqlite)

    return app
}

/// Creates a test application with DatabaseStore initialized and migrations run
func createTestApplicationWithStore() async throws -> (Application, DatabaseStore) {
    let app = try await createTestApplication()
    let store = DatabaseStore(app: app, db: app.db)

    // Run migrations
    try await app.autoMigrate()

    return (app, store)
}

/// Cleans up a test application
func shutdownTestApplication(_ app: Application) async throws {
    try await app.autoRevert()
    try await app.asyncShutdown()
}

// MARK: - Test Fixtures

struct TestFixtures {

    // MARK: - Identifiers

    static let testEmail = "test@example.com"
    static let testEmail2 = "test2@example.com"
    static let testPhone = "+1234567890"
    static let testPhone2 = "+0987654321"
    static let testUsername = "testuser"
    static let testPassword = "hashedpassword123"
    static let testCodeHash = "codesecret123"
    static let testTokenHash = "tokenhash123"

    static var emailIdentifier: Identifier {
        .email(testEmail)
    }

    static var email2Identifier: Identifier {
        .email(testEmail2)
    }

    static var phoneIdentifier: Identifier {
        .phone(testPhone)
    }

    static var phone2Identifier: Identifier {
        .phone(testPhone2)
    }

    static var usernameIdentifier: Identifier {
        .username(testUsername)
    }

    static var federatedIdentifier: Identifier {
        .federated(.named("google"), userId: "google-user-123")
    }

    static var passwordCredential: Credential {
        .password(testPassword)
    }

    // MARK: - Dates

    static var futureDate: Date {
        Date().addingTimeInterval(3600) // 1 hour from now
    }

    static var pastDate: Date {
        Date().addingTimeInterval(-3600) // 1 hour ago
    }

    static var farFutureDate: Date {
        Date().addingTimeInterval(86400 * 30) // 30 days from now
    }
}

// MARK: - Model Helpers

extension UserModel {
    /// Creates a test user with default values
    static func createTest(
        id: UUID? = nil,
        passwordHash: String? = nil
    ) -> UserModel {
        UserModel(id: id, passwordHash: passwordHash)
    }
}

extension IdentifierModel {
    /// Creates a test identifier model with default values
    static func createTest(
        id: UUID? = nil,
        userID: UUID,
        type: String = "email",
        value: String = TestFixtures.testEmail,
        provider: String? = nil,
        verified: Bool = false
    ) -> IdentifierModel {
        IdentifierModel(
            id: id,
            userID: userID,
            type: type,
            value: value,
            provider: provider,
            verified: verified
        )
    }
}

extension RefreshTokenModel {
    /// Creates a test refresh token model with default values
    static func createTest(
        id: UUID? = nil,
        tokenHash: String = TestFixtures.testTokenHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        revokedAt: Date? = nil,
        replacedBy: UUID? = nil
    ) -> RefreshTokenModel {
        RefreshTokenModel(
            id: id,
            tokenHash: tokenHash,
            userID: userID,
            expiresAt: expiresAt,
            revokedAt: revokedAt,
            replacedBy: replacedBy
        )
    }
}

extension EmailVerificationCodeModel {
    /// Creates a test email verification code model with default values
    static func createTest(
        id: UUID? = nil,
        email: String = TestFixtures.testEmail,
        codeHash: String = TestFixtures.testCodeHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        failedAttempts: Int = 0
    ) -> EmailVerificationCodeModel {
        EmailVerificationCodeModel(
            id: id,
            email: email,
            codeHash: codeHash,
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: failedAttempts
        )
    }
}

extension PhoneVerificationCodeModel {
    /// Creates a test phone verification code model with default values
    static func createTest(
        id: UUID? = nil,
        phone: String = TestFixtures.testPhone,
        codeHash: String = TestFixtures.testCodeHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        failedAttempts: Int = 0
    ) -> PhoneVerificationCodeModel {
        PhoneVerificationCodeModel(
            id: id,
            phone: phone,
            codeHash: codeHash,
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: failedAttempts
        )
    }
}

extension EmailPasswordResetCodeModel {
    /// Creates a test email password reset code model with default values
    static func createTest(
        id: UUID? = nil,
        email: String = TestFixtures.testEmail,
        codeHash: String = TestFixtures.testCodeHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        failedAttempts: Int = 0
    ) -> EmailPasswordResetCodeModel {
        EmailPasswordResetCodeModel(
            id: id,
            email: email,
            codeHash: codeHash,
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: failedAttempts
        )
    }
}

extension PhonePasswordResetCodeModel {
    /// Creates a test phone password reset code model with default values
    static func createTest(
        id: UUID? = nil,
        phone: String = TestFixtures.testPhone,
        codeHash: String = TestFixtures.testCodeHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        failedAttempts: Int = 0
    ) -> PhonePasswordResetCodeModel {
        PhonePasswordResetCodeModel(
            id: id,
            phone: phone,
            codeHash: codeHash,
            userID: userID,
            expiresAt: expiresAt,
            failedAttempts: failedAttempts
        )
    }
}

extension ExchangeTokenModel {
    /// Creates a test exchange token model with default values
    static func createTest(
        id: UUID? = nil,
        tokenHash: String = TestFixtures.testTokenHash,
        userID: UUID,
        expiresAt: Date = TestFixtures.futureDate,
        consumedAt: Date? = nil
    ) -> ExchangeTokenModel {
        ExchangeTokenModel(
            id: id,
            tokenHash: tokenHash,
            userID: userID,
            expiresAt: expiresAt,
            consumedAt: consumedAt
        )
    }
}

// MARK: - Passkey Fixtures

extension TestFixtures {

    /// Canonical base64url-encoded credential ID used across passkey tests.
    static let testCredentialID = "Y3JlZGVudGlhbC1pZC10ZXN0"

    /// Small, deterministic COSE_Key-ish byte blob.
    static var testPublicKey: Data {
        Data([0xA5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21])
    }

    /// Deterministic challenge bytes. Chosen small so tests stay readable;
    /// SHA-256 hex is derived via `bytes.sha256Hex`.
    static var testChallengeBytes: Data {
        Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x11, 0x22, 0x33])
    }

    static func makePasskeyCredential(
        credentialID: String = TestFixtures.testCredentialID,
        publicKey: Data = TestFixtures.testPublicKey,
        signCount: UInt32 = 0,
        uvInitialized: Bool = true,
        transports: [AuthenticatorTransport] = [.internal, .hybrid],
        backupEligible: Bool = true,
        isBackedUp: Bool = false,
        aaguid: String? = "00000000-0000-0000-0000-000000000000",
        attestationFormat: String? = "none"
    ) -> PasskeyCredential {
        PasskeyCredential(
            credentialID: credentialID,
            publicKey: publicKey,
            signCount: signCount,
            uvInitialized: uvInitialized,
            transports: transports,
            backupEligible: backupEligible,
            isBackedUp: isBackedUp,
            aaguid: aaguid,
            attestationFormat: attestationFormat
        )
    }

    static func makePasskeyChallenge(
        bytes: Data = TestFixtures.testChallengeBytes,
        kind: PasskeyChallengeKind = .registration,
        expiresAt: Date = TestFixtures.futureDate
    ) -> PasskeyChallenge {
        PasskeyChallenge(bytes: bytes, kind: kind, expiresAt: expiresAt)
    }
}

extension PasskeyCredentialModel {
    /// Creates a test passkey credential model with default values.
    static func createTest(
        id: UUID? = nil,
        userID: UUID,
        credentialID: String = TestFixtures.testCredentialID,
        publicKey: Data = TestFixtures.testPublicKey,
        signCount: UInt32 = 0,
        uvInitialized: Bool = true,
        transports: [AuthenticatorTransport] = [.internal],
        backupEligible: Bool = true,
        isBackedUp: Bool = false,
        aaguid: String? = "00000000-0000-0000-0000-000000000000",
        attestationFormat: String? = "none"
    ) -> PasskeyCredentialModel {
        PasskeyCredentialModel(
            id: id,
            userID: userID,
            credentialID: credentialID,
            publicKey: publicKey,
            signCount: signCount,
            uvInitialized: uvInitialized,
            transports: transports,
            backupEligible: backupEligible,
            isBackedUp: isBackedUp,
            aaguid: aaguid,
            attestationFormat: attestationFormat
        )
    }
}

extension PasskeyChallengeModel {
    /// Creates a test passkey challenge model with default values.
    static func createTest(
        id: UUID? = nil,
        identifier: Identifier? = nil,
        userID: UUID? = nil,
        kind: PasskeyChallengeKind = .registration,
        challengeHash: String = TestFixtures.testChallengeBytes.sha256Hex,
        expiresAt: Date = TestFixtures.futureDate,
        consumedAt: Date? = nil
    ) -> PasskeyChallengeModel {
        PasskeyChallengeModel(
            id: id,
            identifier: identifier,
            userID: userID,
            kind: kind,
            challengeHash: challengeHash,
            expiresAt: expiresAt,
            consumedAt: consumedAt
        )
    }
}
