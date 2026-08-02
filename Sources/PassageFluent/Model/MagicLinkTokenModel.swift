import Foundation
import Passage
import Fluent

final class MagicLinkTokenModel<UserModel: PassageUserModel>: Model, @unchecked Sendable {
    static var schema: String { "magic_link_tokens" }

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "token_hash")
    var tokenHash: String

    @OptionalParent(key: "user_id")
    var user: UserModel?

    @OptionalField(key: "session_token_hash")
    var sessionTokenHash: String?

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "failed_attempts")
    var failedAttempts: Int

    @OptionalField(key: "invalidated_at")
    var invalidatedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        email: String,
        tokenHash: String,
        userID: UserModel.IDValue?,
        sessionTokenHash: String? = nil,
        expiresAt: Date,
        failedAttempts: Int = 0
    ) {
        self.id = id
        self.email = email
        self.tokenHash = tokenHash
        self.$user.id = userID
        self.sessionTokenHash = sessionTokenHash
        self.expiresAt = expiresAt
        self.failedAttempts = failedAttempts
    }
}

extension MagicLinkTokenModel: MagicLinkToken {
    var identifier: Identifier {
        .email(email)
    }
}
