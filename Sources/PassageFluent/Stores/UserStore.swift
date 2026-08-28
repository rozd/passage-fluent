import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct UserStore<UserModel: PassageUserModel>: Passage.UserStore {
        typealias ConcreateUser = UserModel

        let db: any Database

        var userType: UserModel.Type {
            UserModel.self
        }

        func find(byId id: String) async throws -> (any User)? {
            guard let parsedId = UserModel.passageParseUserID(id) else {
                return nil
            }

            let query = UserModel.query(on: db).filter(\._$id == parsedId)
            UserModel.passageEagerLoad(query)

            guard let user = try await query.first() else {
                return nil
            }

            return user
        }

        func create(identifier: Identifier, with credential: Credential?) async throws -> (any User) {
            // Build query to check if identifier already exists
            var existingQuery = IdentifierModel<UserModel>.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            // For federated identifiers, also match on provider
            if identifier.kind == .federated {
                existingQuery = existingQuery.filter(\.$provider == identifier.provider?.description)
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

                let user = try UserModel.passageMakeUser(identifier: identifier, passwordHash: passwordHash)
                try await user.save(on: db)

                let identifierModel = IdentifierModel<UserModel>(
                    userID: try user.requireID(),
                    type: identifier.kind.rawValue,
                    value: identifier.value,
                    provider: identifier.provider?.description,
                    verified: identifier.kind == .federated  // Federated identifiers are pre-verified
                )
                try await identifierModel.save(on: db)

                // Reload user with identifiers for proper response
                try await user.passageRefresh(on: db)

                return user
            }
        }

        func find(byIdentifier identifier: Identifier) async throws -> (any User)? {
            var query = IdentifierModel<UserModel>.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            // For federated identifiers, also match on provider
            if identifier.kind == .federated {
                query = query.filter(\.$provider == identifier.provider?.description)
            }

            let existing = try await query
                .with(\.$user) { user in
                    UserModel.passageEagerLoad(user)
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
            var existingQuery = IdentifierModel<UserModel>.query(on: db)
                .filter(\.$type == identifier.kind.rawValue)
                .filter(\.$value == identifier.value)

            if identifier.kind == .federated {
                existingQuery = existingQuery.filter(\.$provider == identifier.provider?.description)
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

                let identifierModel = IdentifierModel<UserModel>(
                    userID: try user.requireID(),
                    type: identifier.kind.rawValue,
                    value: identifier.value,
                    provider: identifier.provider?.description,
                    verified: identifier.kind == .federated
                )
                try await identifierModel.save(on: db)

                try await user.passageRefresh(on: db)
            }
        }

        func markEmailVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel<UserModel>.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.email.rawValue)
                .set(\.$verified, to: true)
                .update()

            try await UserModel.passageDidMarkIdentifierVerified(.email, for: user, on: db)
            try await user.passageRefresh(on: db)
        }

        func markPhoneVerified(for user: any User) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            try await IdentifierModel<UserModel>.query(on: db)
                .filter(\.$user.$id == user.requireID())
                .filter(\.$type == Identifier.Kind.phone.rawValue)
                .set(\.$verified, to: true)
                .update()

            try await UserModel.passageDidMarkIdentifierVerified(.phone, for: user, on: db)
            try await user.passageRefresh(on: db)
        }

        func setPassword(for user: any User, passwordHash: String) async throws {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            user.passwordHash = passwordHash
            try await user.save(on: db)
        }

        func createWithEmail(_ email: String, verified: Bool) async throws -> any User {
            let user = try await self.create(identifier: .email(email), with: nil)
            if verified {
                try await self.markEmailVerified(for: user)
            }
            return user
        }

        func createWithPhone(_ phone: String, verified: Bool) async throws -> any User {
            let user = try await self.create(identifier: .phone(phone), with: nil)
            if verified {
                try await self.markPhoneVerified(for: user)
            }
            return user
        }
    }

}
