import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct MagicLinkTokenStore<UserModel: PassageUserModel>: Passage.MagicLinkTokenStore {

        let db: any Database

        func createEmailMagicLink(
            for user: (any User)?,
            identifier: Identifier,
            tokenHash: String,
            sessionTokenHash: String?,
            expiresAt: Date,
        ) async throws -> any MagicLinkToken {
            guard identifier.kind == .email else {
                throw PassageError.unexpected(message: "Expected email identifier, got \(identifier.kind)")
            }

            let userID: UserModel.IDValue?
            if let user = user {
                guard let userModel = user as? UserModel else {
                    throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
                }
                userID = try userModel.requireID()
            } else {
                userID = nil
            }

            let model = MagicLinkTokenModel<UserModel>(
                email: identifier.value,
                tokenHash: tokenHash,
                userID: userID,
                sessionTokenHash: sessionTokenHash,
                expiresAt: expiresAt
            )
            try await model.save(on: db)

            if userID != nil {
                try await model.$user.load(on: db)
                try await model.user?.passageRefresh(on: db)
            }

            return model
        }

        func findEmailMagicLink(tokenHash: String) async throws -> (any MagicLinkToken)? {
            let query = MagicLinkTokenModel<UserModel>.query(on: db)
                .filter(\.$tokenHash == tokenHash)
                .filter(\.$invalidatedAt == nil)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func invalidateEmailMagicLinks(for identifier: Identifier) async throws {
            guard identifier.kind == .email else {
                throw PassageError.unexpected(message: "Expected email identifier, got \(identifier.kind)")
            }
            try await MagicLinkTokenModel<UserModel>.query(on: db)
                .filter(\.$email == identifier.value)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for magicLink: any MagicLinkToken) async throws {
            guard let model = magicLink as? MagicLinkTokenModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected magic link type: \(type(of: magicLink))")
            }
            model.failedAttempts += 1
            try await model.save(on: db)
        }

    }
}
