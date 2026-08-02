import Foundation
import Fluent
import FluentKit
import Passage

/// Protocol for user models that work with PassageFluent's generic store.
///
/// Apps can conform their existing Fluent user model to this protocol and inject it
/// via `DatabaseStore.init(app:db:userModelType:)` to enable overlay mode.
///
/// Models conforming to this protocol automatically conform to Passage.User
/// to expose identity properties (email, phone, etc.) used by Passage routes.
public protocol PassageUserModel: FluentKit.Model, User where Id == IDValue {

    /// Passage.User only requires `get`; the generic UserStore needs `set`.
    var passwordHash: String? { get set }

    /// Parse JWT `sub` claim (or session ID string) back to native IDValue.
    /// Called by generic `UserStore.find(byId:)`.
    /// Defaults: UUID via `UUID(uuidString:)`, Int via `Int(_:)`, String identity.
    static func passageParseUserID(_ string: String) -> IDValue?

    /// Database column type for foreign keys in dependent tables.
    /// Defaults: `.uuid` for UUID, `.int` for Int, `.string` for String.
    static var passageUserIDDataType: DatabaseSchema.DataType { get }

    /// Field key on the user table that dependent FK columns reference.
    /// Default: `.id`.
    static var passageUserIDFieldKey: FieldKey { get }

    /// Registration factory. Called by generic `UserStore.create(identifier:with:)`.
    /// Default: `Self()` + `passwordHash` assigned from credential.
    /// Override if your model requires non-null columns to be populated from the identifier.
    static func passageMakeUser(identifier: Identifier, passwordHash: String?) throws -> Self

    /// Eager load this user model's relations (called both top-level and nested).
    /// Called by generic store's find methods before returning to caller.
    /// Default no-op; `UserModel` override: `.with(\.$identifiers)`.
    static func passageEagerLoad<Builder: EagerLoadBuilder>(_ builder: Builder) where Builder.Model == Self

    /// Load relations on an already-materialized instance (post-save sites).
    /// Called after saves in `create`, `addIdentifier`, magic-link/passkey creates.
    /// Default no-op; `UserModel` override: `try await self.$identifiers.load(on: db)`.
    func passageRefresh(on db: any Database) async throws

    /// Called after the generic UserStore marks `IdentifierModel<Self>` rows verified.
    /// Gives models that back `isEmailVerified`/`isPhoneVerified` with own columns a chance to sync.
    /// Default no-op.
    static func passageDidMarkIdentifierVerified(
        _ kind: Identifier.Kind,
        for user: Self,
        on db: any Database
    ) async throws
}

// MARK: - Default Implementations (all types)

extension PassageUserModel {
    public static var passageUserIDFieldKey: FieldKey {
        .id
    }

    public static func passageMakeUser(identifier: Identifier, passwordHash: String?) throws -> Self {
        let user = Self()
        user.passwordHash = passwordHash
        return user
    }

    public static func passageEagerLoad<Builder: EagerLoadBuilder>(_ builder: Builder) where Builder.Model == Self {
        // No-op default; override in models that need eager loading
    }

    public func passageRefresh(on db: any Database) async throws {
        // No-op default; override in models that need post-save reloading
    }

    public static func passageDidMarkIdentifierVerified(
        _ kind: Identifier.Kind,
        for user: Self,
        on db: any Database
    ) async throws {
        // No-op default; override in models that sync verification state to their own columns
    }
}

// MARK: - Constrained Defaults for UUID

extension PassageUserModel where IDValue == UUID {
    public static func passageParseUserID(_ string: String) -> IDValue? {
        UUID(uuidString: string)
    }

    public static var passageUserIDDataType: DatabaseSchema.DataType {
        .uuid
    }
}

// MARK: - Constrained Defaults for Int

extension PassageUserModel where IDValue == Int {
    public static func passageParseUserID(_ string: String) -> IDValue? {
        Int(string)
    }

    public static var passageUserIDDataType: DatabaseSchema.DataType {
        .int
    }
}

// MARK: - Constrained Defaults for String

extension PassageUserModel where IDValue == String {
    public static func passageParseUserID(_ string: String) -> IDValue? {
        string
    }

    public static var passageUserIDDataType: DatabaseSchema.DataType {
        .string
    }
}
