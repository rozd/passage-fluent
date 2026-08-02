import Vapor
import Fluent
import Passage

extension DatabaseStore {

    struct PasskeyChallengeStore<UserModel: PassageUserModel>: Passage.PasskeyChallengeStore {

        let db: any Database

        func createPasskeyChallenge(
            from challenge: PasskeyChallenge
        ) async throws -> any StoredPasskeyChallenge {
            let model = PasskeyChallengeModel<UserModel>(
                userID: nil,
                kind: challenge.kind,
                challengeHash: challenge.bytes.sha256Hex,
                expiresAt: challenge.expiresAt
            )
            try await model.save(on: db)
            return model
        }

        func createPasskeyChallenge(
            for user: any User,
            from challenge: PasskeyChallenge
        ) async throws -> any StoredPasskeyChallenge {
            guard let userModel = user as? UserModel else {
                throw PassageError.unexpected(message: "Unexpected user type: \(type(of: user))")
            }

            let model = PasskeyChallengeModel<UserModel>(
                userID: try userModel.requireID(),
                kind: challenge.kind,
                challengeHash: challenge.bytes.sha256Hex,
                expiresAt: challenge.expiresAt
            )
            try await model.save(on: db)

            try await model.$user.load(on: db)
            try await model.user?.passageRefresh(on: db)

            return model
        }

        func createPasskeyChallenge(
            for identifier: Identifier,
            from challenge: PasskeyChallenge
        ) async throws -> any StoredPasskeyChallenge {
            let model = PasskeyChallengeModel<UserModel>(
                identifier: identifier,
                userID: nil,
                kind: challenge.kind,
                challengeHash: challenge.bytes.sha256Hex,
                expiresAt: challenge.expiresAt
            )
            try await model.save(on: db)
            return model
        }

        func find(passkeyChallengeMatching bytes: Data) async throws -> (any StoredPasskeyChallenge)? {
            let query = PasskeyChallengeModel<UserModel>.query(on: db)
                .filter(\.$challengeHash == bytes.sha256Hex)

            query.with(\.$user) { user in
                UserModel.passageEagerLoad(user)
            }

            return try await query.first()
        }

        func consume(passkeyChallenge: any StoredPasskeyChallenge) async throws {
            guard let model = passkeyChallenge as? PasskeyChallengeModel<UserModel> else {
                throw PassageError.unexpected(message: "Unexpected challenge type: \(type(of: passkeyChallenge))")
            }

            model.consumedAt = .now
            try await model.save(on: db)
        }

        func cleanupExpiredPasskeyChallenges(before date: Date) async throws {
            try await PasskeyChallengeModel<UserModel>.query(on: db)
                .filter(\.$expiresAt < date)
                .delete()
        }
    }
}
