import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct TokenStore<UserModel: PassageUserModel>: Passage.TokenStore {

        let app: Application
        let db: any Database

        func createRefreshToken(
            for user: any User,
            tokenHash hash: String,
            expiresAt: Date,
            sessionId: UUID,
        ) async throws -> any RefreshToken {
            try await self.createRefreshToken(
                for: user,
                tokenHash: hash,
                expiresAt: expiresAt,
                sessionId: sessionId,
                replacing: nil,
            )
        }

        func createRefreshToken(
            for user: any User,
            tokenHash hash: String,
            expiresAt: Date,
            sessionId: UUID,
            replacing tokenToReplace: (any RefreshToken)?,
        ) async throws -> any RefreshToken {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }
            return try await db.transaction { db in
                let newRefreshToken = RefreshTokenModel<UserModel>(
                    tokenHash: hash,
                    userID: try user.requireID(),
                    expiresAt: expiresAt,
                    sessionId: sessionId
                )

                try await newRefreshToken.save(on: db)

                guard let tokenToReplace = tokenToReplace else {
                    return newRefreshToken
                }

                guard let oldRefreshToken = tokenToReplace as? RefreshTokenModel<UserModel> else {
                    throw PassageError.unexpected(message: "Unexpected token type: \(type(of: tokenToReplace))")
                }

                oldRefreshToken.revokedAt = .now
                oldRefreshToken.replacedBy = newRefreshToken.id

                try await oldRefreshToken.save(on: db)

                return newRefreshToken
            }
        }

        func find(refreshTokenHash hash: String) async throws -> (any RefreshToken)? {
            let query = RefreshTokenModel<UserModel>.query(on: db)
                .filter(\.$tokenHash == hash)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func revokeRefreshTokens(for user: any User) async throws -> [UUID] {
            guard let userId = user.id else {
                throw PassageError.unexpected(message: "User ID is missing")
            }

            guard let userIdValue = userId as? UserModel.IDValue else {
                throw PassageError.unexpected(message: "User ID type mismatch")
            }

            return try await db.transaction { db in
                let live = try await RefreshTokenModel<UserModel>.query(on: db)
                    .filter(\.$user.$id == userIdValue)
                    .filter(\.$revokedAt == nil)
                    .all()

                var sessionIds: [UUID] = []
                for token in live where !sessionIds.contains(token.sessionId) {
                    sessionIds.append(token.sessionId)
                }

                try await RefreshTokenModel<UserModel>.query(on: db)
                    .filter(\.$user.$id == userIdValue)
                    .filter(\.$revokedAt == nil)
                    .set(\.$revokedAt, to: .now)
                    .update()

                return sessionIds
            }
        }

        @discardableResult
        func revokeRefreshTokens(
            for user: any User,
            keepingNewestSessions count: Int
        ) async throws -> [UUID] {
            guard let userId = user.id else {
                throw PassageError.unexpected(message: "User ID is missing")
            }

            guard let userIdValue = userId as? UserModel.IDValue else {
                throw PassageError.unexpected(message: "User ID type mismatch")
            }

            if count <= 0 {
                return try await revokeRefreshTokens(for: user)
            }

            return try await db.transaction { db in
                let live = try await RefreshTokenModel<UserModel>.query(on: db)
                    .filter(\.$user.$id == userIdValue)
                    .filter(\.$revokedAt == nil)
                    .sort(\.$createdAt, .descending)
                    .all()

                var orderedSessions: [UUID] = []

                for token in live {
                    if !orderedSessions.contains(token.sessionId) {
                        orderedSessions.append(token.sessionId)
                    }
                }

                let evicted = Array(orderedSessions.dropFirst(count))

                if evicted.isEmpty {
                    return []
                }

                try await RefreshTokenModel<UserModel>.query(on: db)
                    .filter(\.$user.$id == userIdValue)
                    .filter(\.$revokedAt == nil)
                    .filter(\.$sessionId ~~ evicted)
                    .set(\.$revokedAt, to: .now)
                    .update()

                return evicted
            }
        }

        func revokeRefreshTokens(sessionId: UUID) async throws {
            try await RefreshTokenModel<UserModel>.query(on: db)
                .filter(\.$sessionId == sessionId)
                .filter(\.$revokedAt == nil)
                .set(\.$revokedAt, to: .now)
                .update()
        }

        func revokeRefreshToken(withHash hash: String) async throws {
            guard let existingToken = try await RefreshTokenModel<UserModel>.query(on: db)
                .filter(\.$tokenHash == hash)
                .first()
            else {
                return // Token not found, nothing to revoke
            }

            existingToken.revokedAt = .now
            try await existingToken.save(on: db)
        }

        func revoke(refreshTokenFamilyStartingFrom token: any RefreshToken) async throws {
            guard let token = token as? RefreshTokenModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected token type: \(type(of: token))")
            }

            try await db.transaction { db in
                var currentTokenId = token.id

                while let tokenId = currentTokenId {
                    guard let nextToken = try await RefreshTokenModel<UserModel>.find(tokenId, on: db) else {
                        break
                    }

                    if nextToken.revokedAt == nil {
                        nextToken.revokedAt = .now
                        try await nextToken.save(on: db)
                    }

                    currentTokenId = nextToken.replacedBy
                }
            }

        }
    }
}
