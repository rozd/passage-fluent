import Foundation
import Identity
import Fluent

final class EmailResetCodeModel: Model, @unchecked Sendable {
    static let schema = "email_reset_codes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "code_hash")
    var codeHash: String

    @Parent(key: "user_id")
    var user: UserModel

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
        codeHash: String,
        userID: UUID,
        expiresAt: Date,
        failedAttempts: Int = 0
    ) {
        self.id = id
        self.email = email
        self.codeHash = codeHash
        self.$user.id = userID
        self.expiresAt = expiresAt
        self.failedAttempts = failedAttempts
    }
}

extension EmailResetCodeModel: Identity.Restoration.EmailResetCode {

}
