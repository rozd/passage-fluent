import Foundation
import Passage
import Fluent

final class PasskeyCredentialModel: Model, @unchecked Sendable {
    static let schema = "passkey_credentials"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: UserModel

    @Field(key: "credential_id")
    var credentialID: String

    @Field(key: "public_key")
    var publicKey: Data

    @Field(key: "sign_count")
    var signCount: UInt32

    @Field(key: "uv_initialized")
    var uvInitialized: Bool

    @Field(key: "transports")
    var transports: [AuthenticatorTransport]

    @Field(key: "backup_eligible")
    var backupEligible: Bool

    @Field(key: "is_backed_up")
    var isBackedUp: Bool

    @OptionalField(key: "aaguid")
    var aaguid: String?

    @OptionalField(key: "attestation_format")
    var attestationFormat: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        credentialID: String,
        publicKey: Data,
        signCount: UInt32,
        uvInitialized: Bool,
        transports: [AuthenticatorTransport],
        backupEligible: Bool,
        isBackedUp: Bool,
        aaguid: String?,
        attestationFormat: String?
    ) {
        self.id = id
        self.$user.id = userID
        self.credentialID = credentialID
        self.publicKey = publicKey
        self.signCount = signCount
        self.uvInitialized = uvInitialized
        self.transports = transports
        self.backupEligible = backupEligible
        self.isBackedUp = isBackedUp
        self.aaguid = aaguid
        self.attestationFormat = attestationFormat
    }
}

extension PasskeyCredentialModel: StoredPasskeyCredential {}
