import Foundation
import Passage
import Fluent

final class ExchangeTokenModel: Model, @unchecked Sendable {
    static let schema = "exchange_tokens"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token_hash")
    var tokenHash: String

    @Parent(key: "user_id")
    var user: UserModel

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "consumed_at")
    var consumedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        tokenHash: String,
        userID: UUID,
        expiresAt: Date,
        consumedAt: Date? = nil
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.$user.id = userID
        self.expiresAt = expiresAt
        self.consumedAt = consumedAt
    }
}

extension ExchangeTokenModel: ExchangeToken {

}
