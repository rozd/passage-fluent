import Foundation
import Fluent

final class IdentifierModel: Model, @unchecked Sendable {
    static let schema = "identifiers"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: UserModel

    @Field(key: "type")
    var type: String

    @Field(key: "value")
    var value: String

    @OptionalField(key: "provider")
    var provider: String?

    @Field(key: "verified")
    var verified: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, type: String, value: String, provider: String? = nil, verified: Bool = false) {
        self.id = id
        self.$user.id = userID
        self.type = type
        self.value = value
        self.provider = provider
        self.verified = verified
    }
}
