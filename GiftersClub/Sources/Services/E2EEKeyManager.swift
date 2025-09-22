import Foundation
import CryptoKit

final class E2EEKeyManager {
    static let shared = E2EEKeyManager()
    private init() {}

    private let privTag = "club.gifters.keys.e2ee.private"
    private let pubTag = "club.gifters.keys.e2ee.public"

    struct KeyPair {
        let privateKey: Curve25519.KeyAgreement.PrivateKey
        let publicKey: Curve25519.KeyAgreement.PublicKey
    }

    func loadOrGenerate() throws -> KeyPair {
        if let pk = try? loadPrivate() {
            return KeyPair(privateKey: pk, publicKey: pk.publicKey)
        }
        let priv = Curve25519.KeyAgreement.PrivateKey()
        try storePrivate(priv)
        return KeyPair(privateKey: priv, publicKey: priv.publicKey)
    }

    func publicKeyBase64() throws -> String {
        let kp = try loadOrGenerate()
        return kp.publicKey.rawRepresentation.base64EncodedString()
    }

    func sharedSecret(with peerPublicBase64: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: peerPublicBase64) else { throw NSError(domain: "E2EE", code: -1) }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
        let my = try loadOrGenerate().privateKey
        let ss = try my.sharedSecretFromKeyAgreement(with: peer)
        // Derive ChaChaPoly key via HKDF (use empty sharedInfo)
        let key = ss.hkdfDerivedSymmetricKey(using: SHA256.self,
                                             salt: Data("giftersclub-chat".utf8),
                                             sharedInfo: Data(),
                                             outputByteCount: 32)
        return key
    }

    // MARK: - Encrypt/Decrypt (ChaCha20-Poly1305)
    struct Ciphertext: Codable { let v: Int; let alg: String; let ct: String }

    func encrypt(_ plaintext: String, with key: SymmetricKey) throws -> String {
        let box = try ChaChaPoly.seal(Data(plaintext.utf8), using: key)
        // Store combined (nonce+ciphertext+tag) for simpler decoding
        let payload = Ciphertext(v: 1, alg: "chacha20poly1305", ct: box.combined.base64EncodedString())
        let data = try JSONEncoder().encode(payload)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func decrypt(_ blob: String, with key: SymmetricKey) throws -> String {
        guard let data = blob.data(using: .utf8) else { throw NSError(domain: "E2EE", code: -2) }
        let payload = try JSONDecoder().decode(Ciphertext.self, from: data)
        guard let cb = Data(base64Encoded: payload.ct) else { throw NSError(domain: "E2EE", code: -3) }
        let sealed = try ChaChaPoly.SealedBox(combined: cb)
        let pt = try ChaChaPoly.open(sealed, using: key)
        return String(data: pt, encoding: .utf8) ?? ""
    }

    // MARK: - Keychain storage (private key only)
    private func loadPrivate() throws -> Curve25519.KeyAgreement.PrivateKey? {
        var query: [String: Any] = [kSecClass as String: kSecClassKey,
                                    kSecAttrApplicationTag as String: privTag,
                                    kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                                    kSecReturnData as String: true]
        query[kSecAttrSynchronizable as String] = kCFBooleanTrue
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) }
        return nil
    }

    private func storePrivate(_ key: Curve25519.KeyAgreement.PrivateKey) throws {
        let data = key.rawRepresentation
        // Delete any existing
        let delQuery: [String: Any] = [kSecClass as String: kSecClassKey,
                                       kSecAttrApplicationTag as String: privTag,
                                       kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom]
        SecItemDelete(delQuery as CFDictionary)
        // Add
        var add: [String: Any] = [kSecClass as String: kSecClassKey,
                                  kSecAttrApplicationTag as String: privTag,
                                  kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
                                  kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        // Opt into iCloud Keychain sync when available so keys survive reinstalls on same Apple ID
        add[kSecAttrSynchronizable as String] = kCFBooleanTrue
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { throw NSError(domain: "E2EE", code: Int(status)) }
    }
}
