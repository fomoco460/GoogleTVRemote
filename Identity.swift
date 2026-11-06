import Foundation
import Security

enum IdentityError: Error { case keychain(OSStatus), creation, encoding }

// Minimal DER writer for a self-signed RSA client certificate. No shared private key.
enum DER {
    static func node(_ tag: UInt8, _ bytes: Data) -> Data {
        var length = Data()
        if bytes.count < 128 { length.append(UInt8(bytes.count)) }
        else {
            var n = bytes.count; var parts = [UInt8]()
            while n > 0 { parts.insert(UInt8(n & 255), at: 0); n >>= 8 }
            length.append(128 | UInt8(parts.count)); length.append(contentsOf: parts)
        }
        return Data([tag]) + length + bytes
    }
    static func sequence(_ data: Data) -> Data { node(0x30, data) }
    static func integer(_ data: Data) -> Data {
        var bytes = Data(data.drop(while: { $0 == 0 }))
        if bytes.isEmpty { bytes = Data([0]) }
        if bytes.first! & 128 != 0 { bytes.insert(0, at: 0) }
        return node(2, bytes)
    }
    static func contents(_ bytes: [UInt8], _ index: inout Int, tag: UInt8) throws -> Data {
        guard index + 2 <= bytes.count, bytes[index] == tag else { throw IdentityError.encoding }
        index += 1
        var length = Int(bytes[index]); index += 1
        if length & 128 != 0 {
            let count = length & 127
            guard count > 0, count <= 4, index + count <= bytes.count else { throw IdentityError.encoding }
            length = 0
            for _ in 0..<count { length = length * 256 + Int(bytes[index]); index += 1 }
        }
        guard length <= bytes.count - index else { throw IdentityError.encoding }
        defer { index += length }
        return Data(bytes[index..<index + length])
    }
    static func rsaNumbers(_ key: SecKey) throws -> Data {
        guard let external = SecKeyCopyExternalRepresentation(key, nil) as Data? else { throw IdentityError.encoding }
        var i = 0
        let sequence = try contents(Array(external), &i, tag: 0x30)
        i = 0
        let modulus = try contents(Array(sequence), &i, tag: 2)
        let exponent = try contents(Array(sequence), &i, tag: 2)
        return Data(modulus.drop(while: { $0 == 0 })) + Data(exponent.drop(while: { $0 == 0 }))
    }
}

struct ClientIdentity {
    let identity: SecIdentity
    let publicKey: SecKey
    private static let tag = Data("local.google-tv-remote.client-key.v1".utf8)
    private static let label = "Google TV Remote Client v1"

    static func load() throws -> ClientIdentity {
        let identityQuery: [String: Any] = [kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label, kSecReturnRef as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(identityQuery as CFDictionary, &item) == errSecSuccess, let item {
            let identity = item as! SecIdentity
            var key: SecKey?
            guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess,
                  let key, let publicKey = SecKeyCopyPublicKey(key) else { throw IdentityError.creation }
            return ClientIdentity(identity: identity, publicKey: publicKey)
        }
        let keyQuery: [String: Any] = [kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag, kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true]
        var existing: CFTypeRef?
        let key: SecKey
        if SecItemCopyMatching(keyQuery as CFDictionary, &existing) == errSecSuccess, let existing {
            key = existing as! SecKey
        } else {
            let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 2048,
                kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true,
                    kSecAttrApplicationTag as String: tag,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]]
            guard let created = SecKeyCreateRandomKey(attributes as CFDictionary, nil) else { throw IdentityError.creation }
            key = created
        }
        guard let publicKey = SecKeyCopyPublicKey(key),
              let rsa = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else { throw IdentityError.creation }
        let algorithm = DER.sequence(Data([0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b,0x05,0x00]))
        let rsaAlgorithm = DER.sequence(Data([0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00]))
        let name = DER.sequence(DER.node(0x31, DER.sequence(Data([0x06,0x03,0x55,0x04,0x03]) + DER.node(0x0c, Data(label.utf8)))))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let before = DER.node(0x17, Data(formatter.string(from: Date().addingTimeInterval(-86400)).utf8))
        let after = DER.node(0x17, Data(formatter.string(from: Date().addingTimeInterval(10 * 365 * 86400)).utf8))
        let serial = DER.integer(Data(UUID().uuidString.utf8.prefix(16)))
        let tbs = DER.sequence(serial + algorithm + name + DER.sequence(before + after) + name
            + DER.sequence(rsaAlgorithm + DER.node(3, Data([0]) + rsa)))
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData, nil) as Data?,
              let certificate = SecCertificateCreateWithData(nil, DER.sequence(tbs + algorithm + DER.node(3, Data([0]) + signature)) as CFData) else { throw IdentityError.creation }
        let status = SecItemAdd([kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate, kSecAttrLabel as String: label] as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw IdentityError.keychain(status) }
        var identity: CFTypeRef?
        let result = SecItemCopyMatching(identityQuery as CFDictionary, &identity)
        guard result == errSecSuccess, let identity else { throw IdentityError.keychain(result) }
        return ClientIdentity(identity: identity as! SecIdentity, publicKey: publicKey)
    }
}
