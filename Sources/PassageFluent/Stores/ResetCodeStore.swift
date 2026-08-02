import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct ResetCodeStore<UserModel: PassageUserModel>: Passage.RestorationCodeStore {

        let db: any Database

        // MARK: - Email Reset Codes

        func createPasswordResetCode(
            for user: any User,
            email: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any EmailPasswordResetCode {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = EmailPasswordResetCodeModel<UserModel>(
                email: email,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findPasswordResetCode(
            forEmail email: String,
            codeHash: String
        ) async throws -> (any EmailPasswordResetCode)? {
            let query = EmailPasswordResetCodeModel<UserModel>.query(on: db)
                .filter(\.$email == email)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func invalidatePasswordResetCodes(forEmail email: String) async throws {
            try await EmailPasswordResetCodeModel<UserModel>.query(on: db)
                .filter(\.$email == email)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any EmailPasswordResetCode) async throws {
            guard let code = code as? EmailPasswordResetCodeModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }

        // MARK: - Phone Reset Codes

        func createPasswordResetCode(
            for user: any User,
            phone: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any PhonePasswordResetCode {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = PhonePasswordResetCodeModel<UserModel>(
                phone: phone,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findPasswordResetCode(
            forPhone phone: String,
            codeHash: String
        ) async throws -> (any PhonePasswordResetCode)? {
            let query = PhonePasswordResetCodeModel<UserModel>.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func invalidatePasswordResetCodes(forPhone phone: String) async throws {
            try await PhonePasswordResetCodeModel<UserModel>.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any PhonePasswordResetCode) async throws {
            guard let code = code as? PhonePasswordResetCodeModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}
