import Vapor
import Fluent
import FluentKit
import Passage

public final class UserModel: Model, ModelSessionAuthenticatable, @unchecked Sendable {
    public static let schema = "users"

    @ID(key: .id)
    public var id: UUID?

    @Field(key: "password_hash")
    public var passwordHash: String?

    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    public var updatedAt: Date?

    @Children(for: \.$user)
    var identifiers: [IdentifierModel]

    public init() {}

    public init(id: UUID? = nil, passwordHash: String? = nil) {
        self.id = id
        self.passwordHash = passwordHash
    }

}

extension UserModel: User {

    fileprivate var emailIdentifier: IdentifierModel? {
        identifiers.first { $0.type == "email" }
    }

    fileprivate var phoneIdentifier: IdentifierModel? {
        identifiers.first { $0.type == "phone" }
    }

    fileprivate var usernameIdentifier: IdentifierModel? {
        identifiers.first { $0.type == "username" }
    }

    public var email: String? {
        emailIdentifier?.value
    }
    
    public var phone: String? {
        phoneIdentifier?.value
    }
    
    public var username: String? {
        usernameIdentifier?.value
    }
    
    public var isAnonymous: Bool {
        email == nil && phone == nil && username == nil
    }
    
    public var isEmailVerified: Bool {
        emailIdentifier?.verified == true
    }
    
    public var isPhoneVerified: Bool {
        phoneIdentifier?.verified == true
    }

}
