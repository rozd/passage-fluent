//
//  PhoneVerificationCodeModel.swift
//  passten
//
//  Created by Max Rozdobudko on 11/29/25.
//

import Vapor
import Fluent

final class PhoneVerificationCodeModel: Model, @unchecked Sendable {
    static let schema = "phone_verification_codes"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "phone")
    var phone: String

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
        phone: String,
        codeHash: String,
        userID: UUID,
        expiresAt: Date,
        failedAttempts: Int = 0
    ) {
        self.id = id
        self.phone = phone
        self.codeHash = codeHash
        self.$user.id = userID
        self.expiresAt = expiresAt
        self.failedAttempts = failedAttempts
    }
}

extension PhoneVerificationCodeModel: Identity.Verification.PhoneCode {

}
