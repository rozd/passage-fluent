import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct VerificationCodeStore<UserModel: PassageUserModel>: Passage.VerificationCodeStore {

        let db: any Database

        // MARK: - Email Codes

        func createEmailCode(
            for user: any User,
            email: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any EmailVerificationCode {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = EmailVerificationCodeModel<UserModel>(
                email: email,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findEmailCode(
            forEmail email: String,
            codeHash: String
        ) async throws -> (any EmailVerificationCode)? {
            let query = EmailVerificationCodeModel<UserModel>.query(on: db)
                .filter(\.$email == email)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func invalidateEmailCodes(forEmail email: String) async throws {
            try await EmailVerificationCodeModel<UserModel>.query(on: db)
                .filter(\.$email == email)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any EmailVerificationCode) async throws {
            guard let code = code as? EmailVerificationCodeModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }

        // MARK: - Phone Codes

        func createPhoneCode(
            for user: any User,
            phone: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any PhoneVerificationCode {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = PhoneVerificationCodeModel<UserModel>(
                phone: phone,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findPhoneCode(
            forPhone phone: String,
            codeHash: String
        ) async throws -> (any PhoneVerificationCode)? {
            let query = PhoneVerificationCodeModel<UserModel>.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func invalidatePhoneCodes(forPhone phone: String) async throws {
            try await PhoneVerificationCodeModel<UserModel>.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any PhoneVerificationCode) async throws {
            guard let code = code as? PhoneVerificationCodeModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}
