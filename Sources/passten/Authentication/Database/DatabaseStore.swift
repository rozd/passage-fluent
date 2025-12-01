//
//  DatabaseStore.swift
//  passten
//
//  Created by Max Rozdobudko on 11/25/25.
//

import Vapor
import Fluent
import JWT
import Crypto

struct DatabaseStore: Identity.Store {

    let db: any Database

    let users: any Identity.UserStore

    let tokens: any Identity.TokenStore

    let codes: any Identity.CodeStore

    let resetCodes: any Identity.ResetCodeStore

    init(app: Application, db: any Database) {
        self.db = db
        self.users = UserStore(db: db)
        self.tokens = TokenStore(app: app, db: db)
        self.codes = CodeStore(db: db)
        self.resetCodes = ResetCodeStore(db: db)
        app.migrations.add(CreateUserModel())
        app.migrations.add(CreateIdentifierModel())
        app.migrations.add(CreateRefreshTokenModel())
        app.migrations.add(CreateEmailVerificationCodeModel())
        app.migrations.add(CreatePhoneVerificationCodeModel())
        app.migrations.add(CreateEmailResetCodeModel())
        app.migrations.add(CreatePhoneResetCodeModel())
    }
}

extension DatabaseStore {

    struct UserStore: Identity.UserStore {
        let db: any Database

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

        func create(with credential: Credential) async throws {
            let existing = try await IdentifierModel.query(on: db)
                .filter(\.$type == credential.identifier.kind.rawValue)
                .filter(\.$value == credential.identifier.value)
                .first()

            guard existing == nil else {
                throw credential.errorWhenIdentifierAlreadyRegistered
            }

            try await db.transaction { db in
                let user = UserModel(passwordHash: credential.passwordHash)
                try await user.save(on: db)

                let identifier = IdentifierModel(
                    userID: try user.requireID(),
                    type: credential.identifier.kind.rawValue,
                    value: credential.identifier.value,
                    verified: false
                )
                try await identifier.save(on: db)
            }
        }

        func find(byCredential credential: Credential) async throws -> (any User)? {
            let existing = try await IdentifierModel.query(on: db)
                .filter(\.$type == credential.identifier.kind.rawValue)
                .filter(\.$value == credential.identifier.value)
                .with(\.$user)
                .first()

            guard let identifier = existing else {
                throw credential.errorWhenIdentifierIsInvalid
            }

            return identifier.user
        }

        func find(byIdentifier identifier: Identifier) async throws -> (any User)? {
            let existing = try await IdentifierModel.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)
                .with(\.$user) { user in
                    user.with(\.$identifiers)  // Nested eager load
                }
                .first()

            guard let model = existing else {
                throw identifier.errorWhenIdentifierIsInvalid
            }

            return model.user
        }

        func markEmailVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.email.rawValue)
                .set(\.$verified, to: true)
                .update()
        }

        func markPhoneVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.phone.rawValue)
                .set(\.$verified, to: true)
                .update()
        }

        func setPassword(for user: any User, passwordHash: String) async throws {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            user.passwordHash = passwordHash
            try await user.save(on: db)
        }

    }

}

// MARK: - TokenStore

extension DatabaseStore {

    struct TokenStore: Identity.TokenStore {

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
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
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
                    throw IdentityError.unexpected(message: "Unexpected token type: \(type(of: tokenToReplace))")
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
                throw IdentityError.unexpected(message: "User ID is missing")
            }

            guard let userUUID = userId as? UUID else {
                throw IdentityError.unexpected(message: "User ID must be UUID")
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
                throw IdentityError.unexpected(message: "Unexpected token type: \(type(of: token))")
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

    struct CodeStore: Identity.CodeStore {

        let db: any Database

        // MARK: - Email Codes

        func createEmailCode(
            for user: any User,
            email: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any Identity.Verification.EmailCode {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
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
        ) async throws -> (any Identity.Verification.EmailCode)? {
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

        func incrementFailedAttempts(for code: any Identity.Verification.EmailCode) async throws {
            guard let code = code as? EmailVerificationCodeModel else {
                throw IdentityError.unexpected(message: "Unexpected code type: \(type(of: code))")
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
        ) async throws -> any Identity.Verification.PhoneCode {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
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
        ) async throws -> (any Identity.Verification.PhoneCode)? {
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

        func incrementFailedAttempts(for code: any Identity.Verification.PhoneCode) async throws {
            guard let code = code as? PhoneVerificationCodeModel else {
                throw IdentityError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}

// MARK: - ResetCodeStore

extension DatabaseStore {

    struct ResetCodeStore: Identity.ResetCodeStore {

        let db: any Database

        // MARK: - Email Reset Codes

        func createEmailResetCode(
            for user: any User,
            email: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any Identity.Restoration.EmailResetCode {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = EmailResetCodeModel(
                email: email,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findEmailResetCode(
            forEmail email: String,
            codeHash: String
        ) async throws -> (any Identity.Restoration.EmailResetCode)? {
            try await EmailResetCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidateEmailResetCodes(forEmail email: String) async throws {
            try await EmailResetCodeModel.query(on: db)
                .filter(\.$email == email)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any Identity.Restoration.EmailResetCode) async throws {
            guard let code = code as? EmailResetCodeModel else {
                throw IdentityError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }

        // MARK: - Phone Reset Codes

        func createPhoneResetCode(
            for user: any User,
            phone: String,
            codeHash: String,
            expiresAt: Date
        ) async throws -> any Identity.Restoration.PhoneResetCode {
            guard let user = user as? UserModel else {
                throw IdentityError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let code = PhoneResetCodeModel(
                phone: phone,
                codeHash: codeHash,
                userID: try user.requireID(),
                expiresAt: expiresAt
            )
            try await code.save(on: db)
            return code
        }

        func findPhoneResetCode(
            forPhone phone: String,
            codeHash: String
        ) async throws -> (any Identity.Restoration.PhoneResetCode)? {
            try await PhoneResetCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$codeHash == codeHash)
                .filter(\.$invalidatedAt == nil)
                .with(\.$user) { user in
                    user.with(\.$identifiers)
                }
                .first()
        }

        func invalidatePhoneResetCodes(forPhone phone: String) async throws {
            try await PhoneResetCodeModel.query(on: db)
                .filter(\.$phone == phone)
                .filter(\.$invalidatedAt == nil)
                .set(\.$invalidatedAt, to: .now)
                .update()
        }

        func incrementFailedAttempts(for code: any Identity.Restoration.PhoneResetCode) async throws {
            guard let code = code as? PhoneResetCodeModel else {
                throw IdentityError.unexpected(message: "Unexpected code type: \(type(of: code))")
            }
            code.failedAttempts += 1
            try await code.save(on: db)
        }
    }
}
