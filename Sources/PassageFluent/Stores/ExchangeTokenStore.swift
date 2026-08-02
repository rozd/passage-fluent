import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct ExchangeTokenStore<UserModel: PassageUserModel>: Passage.ExchangeTokenStore {

        let db: any Database

        func createExchangeToken(
            for user: any User,
            tokenHash: String,
            expiresAt: Date
        ) async throws -> any ExchangeToken {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            return try await db.transaction { db in
                let token = ExchangeTokenModel<UserModel>(
                    tokenHash: tokenHash,
                    userID: try user.requireID(),
                    expiresAt: expiresAt
                )
                try await token.save(on: db)

                // Eager load user for return
                try await token.$user.load(on: db)
                try await token.user.passageRefresh(on: db)

                return token
            }
        }

        func find(exchangeTokenHash hash: String) async throws -> (any ExchangeToken)? {
            let query = ExchangeTokenModel<UserModel>.query(on: db)
                .filter(\.$tokenHash == hash)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func consume(exchangeToken: any ExchangeToken) async throws {
            guard let model = exchangeToken as? ExchangeTokenModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected token type: \(type(of: exchangeToken))")
            }

            model.consumedAt = Date()
            try await model.save(on: db)
        }

        func cleanupExpiredTokens(before date: Date) async throws {
            try await ExchangeTokenModel<UserModel>.query(on: db)
                .filter(\.$expiresAt < date)
                .delete()
        }
    }
}
