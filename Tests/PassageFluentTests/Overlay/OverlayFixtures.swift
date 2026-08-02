import Foundation
import Vapor
import Fluent
import FluentSQLiteDriver
@testable import PassageFluent
@testable import Passage

// MARK: - AppUser Fixture

/// Example overlay-mode user model with Int ID and stored email column.
/// Demonstrates conformance to PassageUserModel for custom user tables.
final class AppUser: Model, PassageUserModel, ModelSessionAuthenticatable, @unchecked Sendable {
    static let schema = "app_users"

    @ID(custom: "id", generatedBy: .database)
    var id: Int?

    @Field(key: "email")
    var storedEmail: String

    @Field(key: "email_verified")
    var emailVerified: Bool

    @OptionalField(key: "password_hash")
    var passwordHash: String?

    // Protocol-required optional properties
    private var _email: String? { storedEmail.isEmpty ? nil : storedEmail }
    private var _phone: String? { nil }
    private var _username: String? { nil }

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {
        self.storedEmail = ""
        self.emailVerified = false
    }

    init(id: Int? = nil, email: String, emailVerified: Bool = false, passwordHash: String? = nil) {
        self.id = id
        self.storedEmail = email
        self.emailVerified = emailVerified
        self.passwordHash = passwordHash
    }

    // MARK: - PassageUserModel Conformance

    static func passageMakeUser(identifier: Identifier, passwordHash: String?) throws -> AppUser {
        // Require email for new users
        guard identifier.kind == .email else {
            throw PassageError.unexpected(message: "AppUser requires email identifier")
        }
        return AppUser(email: identifier.value, passwordHash: passwordHash)
    }

    static func passageDidMarkIdentifierVerified(
        _ kind: Identifier.Kind,
        for user: AppUser,
        on db: any Database
    ) async throws {
        // Sync email verification state to AppUser.email_verified column
        if kind == .email {
            user.emailVerified = true
            try await user.save(on: db)
        }
    }
}

// MARK: - AppUser Passage.User Conformance

extension AppUser: User {
    public var email: String? { _email }
    public var phone: String? { _phone }
    public var username: String? { _username }

    public var isAnonymous: Bool {
        storedEmail.isEmpty
    }

    public var isEmailVerified: Bool {
        emailVerified
    }

    public var isPhoneVerified: Bool {
        false
    }
}

// MARK: - CreateAppUser Migration

struct CreateAppUser: AsyncMigration {
    let name = "CreateAppUser"

    func prepare(on database: any Database) async throws {
        try await database.schema(AppUser.schema)
            .field("id", .int, .identifier(auto: true))
            .field("email", .string, .required)
            .field("email_verified", .bool, .required)
            .field("password_hash", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "email")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(AppUser.schema).delete()
    }
}

// MARK: - Test Helper

/// Creates a test application pre-configured for overlay mode with AppUser.
func createTestApplicationForOverlay() async throws -> Application {
    let app = try await Application.make(.testing)
    app.databases.use(.sqlite(.memory), as: .sqlite)

    // Register AppUser table migration BEFORE DatabaseStore (FK ordering requirement)
    app.migrations.add(CreateAppUser())

    return app
}
