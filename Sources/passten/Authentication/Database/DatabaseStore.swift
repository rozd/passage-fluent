//
//  DatabaseStore.swift
//  passten
//
//  Created by Max Rozdobudko on 11/25/25.
//

import Vapor
import Fluent

struct DatabaseStore: Authentication.Store {

    let db: any Database

    let users: any Authentication.UserStore

    init(app: Application, db: any Database) {
        self.db = db
        self.users = UserStore(db: db)
        app.migrations.add(CreateUserModel())
        app.migrations.add(CreateIdentifierModel())
    }
}

extension DatabaseStore {

    struct UserStore: Authentication.UserStore {
        let db: any Database

        func create(with credential: Credential) async throws {
            let existing = try await IdentifierModel.query(on: db)
                .filter(\.$type == credential.identifier.kind.rawValue)
                .filter(\.$value == credential.identifier.value)
                .first()

            guard existing == nil else {
                throw AuthenticationError.emailAlreadyRegistered
            }

            let user = try await db.transaction { db in
                let user = UserModel(passwordHash: credential.passwordHash)
                try await user.save(on: db)

                let identifier = IdentifierModel(
                    userID: try user.requireID(),
                    type: credential.identifier.kind.rawValue,
                    value: credential.identifier.value,
                    verified: false
                )
                try await identifier.save(on: db)

                return user
            }
        }

        func find(byCredential credential: Credential) async throws -> (any User)? {
            let existing = try await IdentifierModel.query(on: db)
                .filter(\.$type == credential.identifier.kind.rawValue)
                .filter(\.$value == credential.identifier.value)
                .with(\.$user)
                .first()

            guard let identifier = existing else {
                throw credential.errorWhenIdentifierIsNotRegistered
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
                throw identifier.errorWhenIdentifierIsNotRegistered
            }

            return model.user
        }

    }


}
