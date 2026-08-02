import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct PasskeyCredentialStore<UserModel: PassageUserModel>: Passage.PasskeyCredentialStore {

        let db: any Database

        func createPasskeyCredential(
            for user: any User,
            from credential: PasskeyCredential
        ) async throws -> any StoredPasskeyCredential {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            return try await db.transaction { db in
                let model = PasskeyCredentialModel<UserModel>(
                    userID: try user.requireID(),
                    credentialID: credential.credentialID,
                    publicKey: credential.publicKey,
                    signCount: credential.signCount,
                    uvInitialized: credential.uvInitialized,
                    transports: credential.transports,
                    backupEligible: credential.backupEligible,
                    isBackedUp: credential.isBackedUp,
                    aaguid: credential.aaguid,
                    attestationFormat: credential.attestationFormat
                )
                try await model.save(on: db)

                try await model.$user.load(on: db)
                try await model.user.passageRefresh(on: db)

                return model
            }
        }

        func find(byCredentialID credentialID: String) async throws -> (any StoredPasskeyCredential)? {
            let query = PasskeyCredentialModel<UserModel>.query(on: db)
                .filter(\.$credentialID == credentialID)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func listPasskeyCredentials(forUser user: any User) async throws -> [any StoredPasskeyCredential] {
            guard let user = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let userId = try user.requireID()
            let query = PasskeyCredentialModel<UserModel>.query(on: db)
                .filter(\.$user.$id == userId)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.all()
        }

        func updatePasskeyCredentialAfterAuthentication(
            forCredentialID credentialID: String,
            newSignCount: UInt32,
            isBackedUp: Bool
        ) async throws {
            guard let model = try await PasskeyCredentialModel<UserModel>.query(on: db)
                .filter(\.$credentialID == credentialID)
                .first()
            else {
                return
            }

            model.signCount = newSignCount
            model.isBackedUp = isBackedUp
            try await model.save(on: db)
        }

        func deletePasskeyCredential(byCredentialID credentialID: String) async throws {
            try await PasskeyCredentialModel<UserModel>.query(on: db)
                .filter(\.$credentialID == credentialID)
                .delete()
        }
    }
}
