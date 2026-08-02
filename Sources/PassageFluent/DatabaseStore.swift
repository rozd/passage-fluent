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

    public let passkeyCredentials: (any Passage.PasskeyCredentialStore)?

    public let passkeyChallenges: (any Passage.PasskeyChallengeStore)?

    // MARK: - Public Initializers

    /// Island mode: creates own users table and uses built-in DefaultUserModel
    public init(app: Application, db: any Database) {
        self.init(
            app: app,
            db: db,
            userModelType: DefaultUserModel.self,
            customUserStore: nil,
            includeIdentifiers: true,
            registerMigrations: true
        )
    }

    /// Overlay mode S1: inject custom user model type
    public init<UserModel: PassageUserModel>(
        app: Application,
        db: any Database,
        userModelType: UserModel.Type,
        registerMigrations: Bool = true
    ) {
        self.init(
            app: app,
            db: db,
            userModelType: userModelType,
            customUserStore: nil,
            includeIdentifiers: true,
            registerMigrations: registerMigrations
        )
    }

    /// Overlay mode S3: inject custom user model and custom user store.
    /// Neither the `users` nor `identifiers` tables/migrations are created;
    /// `userStore` must return instances of `userModelType`.
    public init<UserModel: PassageUserModel>(
        app: Application,
        db: any Database,
        userModelType: UserModel.Type,
        userStore: any Passage.UserStore,
        registerMigrations: Bool = true
    ) {
        self.init(
            app: app,
            db: db,
            userModelType: userModelType,
            customUserStore: userStore,
            includeIdentifiers: false,
            registerMigrations: registerMigrations
        )
    }

    private init<UserModel: PassageUserModel>(
        app: Application,
        db: any Database,
        userModelType: UserModel.Type,
        customUserStore: (any Passage.UserStore)?,
        includeIdentifiers: Bool,
        registerMigrations: Bool
    ) {
        self.db = db
        if let customUserStore {
            self.users = customUserStore
        } else {
            self.users = UserStore<UserModel>(db: db)
        }
        self.tokens = TokenStore<UserModel>(app: app, db: db)
        self.verificationCodes = VerificationCodeStore<UserModel>(db: db)
        self.restorationCodes = ResetCodeStore<UserModel>(db: db)
        self.magicLinkTokens = MagicLinkTokenStore<UserModel>(db: db)
        self.exchangeTokens = ExchangeTokenStore<UserModel>(db: db)
        self.passkeyCredentials = PasskeyCredentialStore<UserModel>(db: db)
        self.passkeyChallenges = PasskeyChallengeStore<UserModel>(db: db)

        if registerMigrations {
            Self.registerMigrations(for: UserModel.self, on: app, includeIdentifiers: includeIdentifiers)
        }
    }

    // MARK: - Migration Management

    private static func registerMigrations<UserModel: PassageUserModel>(
        for userModelType: UserModel.Type,
        on app: Application,
        includeIdentifiers: Bool
    ) {
        let isIslandMode = UserModel.self is DefaultUserModel.Type
        let migrations = Self.migrations(for: UserModel.self, includeIdentifiers: includeIdentifiers, isIslandMode: isIslandMode)
        for migration in migrations {
            app.migrations.add(migration)
        }
    }

    /// Returns all migrations for the given user model type.
    /// - Parameter includeIdentifiers: Include the IdentifierModel migration (S1 overlay only; S3 skips it).
    /// - Parameter isIslandMode: Include the DefaultUserModel migration (island mode only).
    public static func migrations<UserModel: PassageUserModel>(
        for userModelType: UserModel.Type,
        includeIdentifiers: Bool = true,
        isIslandMode: Bool = false
    ) -> [AsyncMigration] {
        var migrations: [AsyncMigration] = []

        // Island mode only
        if isIslandMode {
            migrations.append(CreateUserModel())
        }

        // S1 overlay (includeIdentifiers) only; S3 skips
        if includeIdentifiers {
            migrations.append(CreateIdentifierModel<UserModel>())
        }

        // All modes register these 9 dependent migrations
        migrations.append(CreateRefreshTokenModel<UserModel>())
        migrations.append(CreateEmailVerificationCodeModel<UserModel>())
        migrations.append(CreatePhoneVerificationCodeModel<UserModel>())
        migrations.append(CreateEmailResetCodeModel<UserModel>())
        migrations.append(CreatePhoneResetCodeModel<UserModel>())
        migrations.append(CreateExchangeTokenModel<UserModel>())
        migrations.append(CreateMagicLinkTokenModel<UserModel>())
        migrations.append(CreatePasskeyCredentialModel<UserModel>())
        migrations.append(CreatePasskeyChallengeModel<UserModel>())

        return migrations
    }
}
