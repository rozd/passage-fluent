import Vapor
import Fluent
import Crypto
import Passage

public struct DatabaseStore: Passage.Store {

    let db: any Database

    public let users: any Passage.UserStore

    public let tokens: any Passage.TokenStore

    public let verificationCodes: any Passage.VerificationCodeStore

    public let restorationCodes: any Passage.RestorationCodeStore

    public let magicLinkTokens: any Passage.MagicLinkTokenStore

    public let exchangeTokens: any Passage.ExchangeTokenStore

    public init(app: Application, db: any Database) {
        self.db = db
        self.users = UserStore(db: db)
        self.tokens = TokenStore(app: app, db: db)
        self.verificationCodes = VerificationCodeStore(db: db)
        self.restorationCodes = ResetCodeStore(db: db)
        self.magicLinkTokens = MagicLinkTokenStore(db: db)
        self.exchangeTokens = ExchangeTokenStore(db: db)
        app.migrations.add(CreateUserModel())
        app.migrations.add(CreateIdentifierModel())
        app.migrations.add(CreateRefreshTokenModel())
        app.migrations.add(CreateEmailVerificationCodeModel())
        app.migrations.add(CreatePhoneVerificationCodeModel())
        app.migrations.add(CreateEmailResetCodeModel())
        app.migrations.add(CreatePhoneResetCodeModel())
        app.migrations.add(CreateExchangeTokenModel())
    }
}

extension DatabaseStore {

    struct UserStore: Passage.UserStore {
        typealias ConcreateUser = UserModel

        let db: any Database

        var userType: UserModel.Type {
            UserModel.self
        }

        func find(byId id: String) async throws -> (any User)? {
            guard let uuid = UUID(uuidString: id) else {
                return nil
            }

            guard let user = try await UserModel.query(on: db)
                .filter(\.$id == uuid)
                .with(\.$identifiers)
                .first()
            else {
                return nil
            }

            return user
        }

        func create(identifier: Identifier, with credential: Credential?) async throws -> (any User) {
            // Build query to check if identifier already exists
            var existingQuery = IdentifierModel.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            // For federated identifiers, also match on provider
            if identifier.kind == .federated {
                existingQuery = existingQuery.filter(\.$provider == identifier.provider)
            }

            let existing = try await existingQuery.first()

            guard existing == nil else {
                throw identifier.errorWhenIdentifierAlreadyRegistered
            }

            return try await db.transaction { db in
                // Extract password hash from credential if present
                let passwordHash: String? = if let credential = credential, credential.kind == .password {
                    credential.secret
                } else {
                    nil
                }

                let user = UserModel(passwordHash: passwordHash)
                try await user.save(on: db)

                let identifierModel = IdentifierModel(
                    userID: try user.requireID(),
                    type: identifier.kind.rawValue,
                    value: identifier.value,
                    provider: identifier.provider,
                    verified: identifier.kind == .federated  // Federated identifiers are pre-verified
                )
                try await identifierModel.save(on: db)

                // Reload user with identifiers for proper response
                user.$identifiers.value = [identifierModel]

                return user
            }
        }

        func find(byIdentifier identifier: Identifier) async throws -> (any User)? {
            var query = IdentifierModel.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            // For federated identifiers, also match on provider
            if identifier.kind == .federated {
                query = query.filter(\.$provider == identifier.provider)
            }

            let existing = try await query
                .with(\.$user) { user in
                    user.with(\.$identifiers)  // Nested eager load
                }
                .first()

            guard let model = existing else {
                return nil
            }

            return model.user
        }

        func addIdentifier(
            _ identifier: Identifier,
            to user: any User,
            with credential: Credential?
        ) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            // Check if identifier already exists
            var existingQuery = IdentifierModel.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            if identifier.kind == .federated {
                existingQuery = existingQuery.filter(\.$provider == identifier.provider)
            }

            let existing = try await existingQuery.first()

            guard existing == nil else {
                throw identifier.errorWhenIdentifierAlreadyRegistered
            }

            try await db.transaction { db in
                // If credential provided, update password hash
                if let credential = credential, credential.kind == .password {
                    user.passwordHash = credential.secret
                    try await user.save(on: db)
                }

                let identifierModel = IdentifierModel(
                    userID: try user.requireID(),
                    type: identifier.kind.rawValue,
                    value: identifier.value,
                    provider: identifier.provider,
                    verified: identifier.kind == .federated
                )
                try await identifierModel.save(on: db)
            }
        }

        func markEmailVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.email.rawValue)
                .set(\.$verified, to: true)
                .update()
        }

        func markPhoneVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.phone.rawValue)
                .set(\.$verified, to: true)
                .update()
        }

        func setPassword(for user: any User, passwordHash: String) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            user.passwordHash = passwordHash
            try await user.save(on: db)
        }

        func createWithEmail(_ email: String, verified: Bool) async throws -> any User {
            throw PassageError.unexpected(message: "Not implemented yet")
        }

        func createWithPhone(_ phone: String, verified: Bool) async throws -> any User {
            throw PassageError.unexpected(message: "Not implemented yet")
        }


    }

}

// MARK: - TokenStore

extension DatabaseStore {

    struct TokenStore: Passage.TokenStore {

        let app: Application
        let db: any Database

        func createRefreshToken(
            for user: any User,
            tokenHash hash: String,
            expiresAt: Date,
        ) async throws -> any RefreshToken {
            return try await self.createRefreshToken(
                for: user,
                tokenHash: hash,
                expiresAt: expiresAt,
                replacing: nil,
            )
        }

        func createRefreshToken(
            for user: any User,
            tokenHash hash: String,
            expiresAt: Date,
            replacing tokenToReplace: (any RefreshToken)?,
        ) async throws -> any RefreshToken {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }
            return try await db.transaction { db in
                let newRefreshToken = RefreshTokenModel(
                    tokenHash: hash,
                    userID: try user.requireID(),
                    expiresAt: expiresAt
                )

                try await newRefreshToken.save(on: db)

                guard let tokenToReplace = tokenToReplace else {
                    return newRefreshToken
                }

                guard let oldRefreshToken = tokenToReplace as? RefreshTokenModel else {
                    throw PassageError.unexpected(message: "Unexpected token type: \(type(of: tokenToReplace))")
                }

                oldRefreshToken.revokedAt = .now
                oldRefreshToken.replacedBy = newRefreshToken.id

                try await oldRefreshToken.save(on: db)

                return newRefreshToken
            }
        }

        func find(refreshTokenHash hash: String) async throws -> (any RefreshToken)? {
            return try await RefreshTokenModel.query(on: db)
                .filter(\.$tokenHash == hash)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func revokeRefreshToken(for user: any User) async throws {
            guard let userId = user.id else {
                throw PassageError.unexpected(message: "User ID is missing")
            }

            guard let userUUID = userId as? UUID else {
                throw PassageError.unexpected(message: "User ID must be UUID")
            }

            try await RefreshTokenModel.query(on: db)
                .filter(\.$user.$id == userUUID)
                .filter(\.$revokedAt == nil)
                .set(\.$revokedAt, to: .now)
                .update()
        }

        func revokeRefreshToken(withHash hash: String) async throws {
            guard let existingToken = try await RefreshTokenModel.query(on: db)
                .filter(\.$tokenHash == hash)
                .first()
            else {
                return // Token not found, nothing to revoke
            }

            existingToken.revokedAt = .now
            try await existingToken.save(on: db)
        }

        func revoke(refreshTokenFamilyStartingFrom token: any RefreshToken) async throws {
            guard let token = token as? RefreshTokenModel else {
                throw PassageError.unexpected(message: "Unexpected token type: \(type(of: token))")
            }

            try await db.transaction { db in
                var currentTokenId = token.id

                while let tokenId = currentTokenId {
                    guard let nextToken = try await RefreshTokenModel.find(tokenId, on: db) else {
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

// MARK: - CodeStore

extension DatabaseStore {

    struct VerificationCodeStore: Passage.VerificationCodeStore {

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

            let code = EmailVerificationCodeModel(
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
            try await EmailVerificationCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidateEmailCodes(forEmail email: String) async throws {
            try await EmailVerificationCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any EmailVerificationCode) async throws {
            guard let code = code as? EmailVerificationCodeModel else {
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

            let code = PhoneVerificationCodeModel(
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
            try await PhoneVerificationCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidatePhoneCodes(forPhone phone: String) async throws {
            try await PhoneVerificationCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any PhoneVerificationCode) async throws {
            guard let code = code as? PhoneVerificationCodeModel else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}

// MARK: - ResetCodeStore

extension DatabaseStore {

    struct ResetCodeStore: Passage.RestorationCodeStore {

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

            let code = EmailPasswordResetCodeModel(
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
            try await EmailPasswordResetCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidatePasswordResetCodes(forEmail email: String) async throws {
            try await EmailPasswordResetCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any EmailPasswordResetCode) async throws {
            guard let code = code as? EmailPasswordResetCodeModel else {
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

            let code = PhonePasswordResetCodeModel(
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
            try await PhonePasswordResetCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidatePasswordResetCodes(forPhone phone: String) async throws {
            try await PhonePasswordResetCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any PhonePasswordResetCode) async throws {
            guard let code = code as? PhonePasswordResetCodeModel else {
                throw PassageError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}

// MARK: - MagicLinkTokenStore

extension DatabaseStore {

    struct MagicLinkTokenStore: Passage.MagicLinkTokenStore {

        let db: any Database

        func createEmailMagicLink(
            for user: (any User)?,
            identifier: Identifier,
            tokenHash: String,
            sessionTokenHash: String?,
            expiresAt: Date,
        ) async throws -> any MagicLinkToken {
            throw PassageError.unexpected(message: "Not implemented yet")
        }

        func findEmailMagicLink(tokenHash: String) async throws -> (any MagicLinkToken)? {
            throw PassageError.unexpected(message: "Not implemented yet")
        }

        func invalidateEmailMagicLinks(for identifier: Identifier) async throws {
            throw PassageError.unexpected(message: "Not implemented yet")
        }

        func incrementFailedAttempts(for magicLink: any MagicLinkToken) async throws {
            throw PassageError.unexpected(message: "Not implemented yet")
        }

    }
}

// MARK: - ExchangeTokenStore

extension DatabaseStore {

    struct ExchangeTokenStore: Passage.ExchangeTokenStore {

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
                let token = ExchangeTokenModel(
                    tokenHash: tokenHash,
                    userID: try user.requireID(),
                    expiresAt: expiresAt
                )
                try await token.save(on: db)

                // Eager load user for return
                try await token.$user.load(on: db)
                try await token.user.$identifiers.load(on: db)

                return token
            }
        }

        func find(exchangeTokenHash hash: String) async throws -> (any ExchangeToken)? {
            try await ExchangeTokenModel.query(on: db)
                .filter(\.$tokenHash == hash)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func consume(exchangeToken: any ExchangeToken) async throws {
            guard let model = exchangeToken as? ExchangeTokenModel else {
                throw PassageError.unexpected(message: "Unexpected token type: \(type(of: exchangeToken))")
            }

            model.consumedAt = Date()
            try await model.save(on: db)
        }

        func cleanupExpiredTokens(before date: Date) async throws {
            try await ExchangeTokenModel.query(on: db)
                .filter(\.$expiresAt < date)
                .delete()
        }
    }
}
