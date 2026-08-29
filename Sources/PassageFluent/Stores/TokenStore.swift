import Vapor
import Fluent
import SQLKit
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
                try await Self.lockSessions(of: userIdValue, on: db)

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
                try await Self.lockSessions(of: userIdValue, on: db)

                // Only sessions that can still be used compete for the retained
                // slots. An expired-but-unrevoked row must not count as a live
                // session, or a valid session could be evicted in its place.
                let live = try await RefreshTokenModel<UserModel>.query(on: db)
                    .filter(\.$user.$id == userIdValue)
                    .filter(\.$revokedAt == nil)
                    .filter(\.$expiresAt > .now)
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

        /// Serialises concurrent session issuance for one user.
        ///
        /// The concurrency policies rank a user's live sessions and then revoke
        /// the losers. Two overlapping logins that both rank the same committed
        /// snapshot would each miss the other's not-yet-visible insert, evict the
        /// same old sessions, and leave more sessions active than the policy
        /// allows. Row locks on the token table cannot prevent this — the row that
        /// escapes the ranking does not exist yet — so the transaction takes an
        /// exclusive lock on the user row instead. A competing transaction blocks
        /// here until the first commits, and its ranking query then runs as a
        /// fresh statement that sees the committed insert.
        ///
        /// Must run inside the same transaction as the subsequent
        /// `createRefreshToken` insert (the core issues credentials inside
        /// `store.transaction`, and nested `transaction` calls reuse that
        /// connection), otherwise the lock is released before the insert.
        ///
        /// Emits `SELECT ... FOR UPDATE` where the SQL dialect supports it
        /// (PostgreSQL, MySQL). SQLite has no row locks but serialises writers,
        /// so the clause is omitted there; non-SQL databases skip the lock.
        private static func lockSessions(of userId: UserModel.IDValue, on db: any Database) async throws {
            guard let sql = db as? any SQLDatabase else { return }

            let idColumn = SQLIdentifier(UserModel.passageUserIDFieldKey.description)

            try await sql.select()
                .column(idColumn)
                .from(SQLQualifiedTable(UserModel.schema, space: UserModel.space))
                .where(idColumn, .equal, SQLBind(userId))
                .for(.update)
                .run()
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
