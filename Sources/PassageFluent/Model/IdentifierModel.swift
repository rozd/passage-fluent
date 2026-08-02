import Foundation
import Fluent

public final class IdentifierModel<UserModel: PassageUserModel>: Model, @unchecked Sendable {
    public static var schema: String { "identifiers" }

    @ID(key: .id)
    public var id: UUID?

    @Parent(key: "user_id")
    public var user: UserModel

    @Field(key: "type")
    public var type: String

    @Field(key: "value")
    public var value: String

    @OptionalField(key: "provider")
    public var provider: String?

    @Field(key: "verified")
    public var verified: Bool

    @Timestamp(key: "created_at", on: .create)
    public var createdAt: Date?

    public init() {}

    public init(id: UUID? = nil, userID: UserModel.IDValue, type: String, value: String, provider: String? = nil, verified: Bool = false) {
        self.id = id
        self.$user.id = userID
        self.type = type
        self.value = value
        self.provider = provider
        self.verified = verified
    }
}
