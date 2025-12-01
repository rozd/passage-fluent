import Vapor
import Fluent
import FluentKit
import Identity

final class UserModel: Model, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "password_hash")
    var passwordHash: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$user)
    var identifiers: [IdentifierModel]

    init() {}

    init(id: UUID? = nil, passwordHash: String? = nil) {
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

    var email: String? {
        emailIdentifier?.value
    }
    
    var phone: String? {
        phoneIdentifier?.value
    }
    
    var username: String? {
        usernameIdentifier?.value
    }
    
    var isAnonymous: Bool {
        email == nil && phone == nil && username == nil
    }
    
    var isEmailVerified: Bool {
        emailIdentifier?.verified == true
    }
    
    var isPhoneVerified: Bool {
        phoneIdentifier?.verified == true
    }
    

}
