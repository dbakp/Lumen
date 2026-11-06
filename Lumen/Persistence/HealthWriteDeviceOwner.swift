import Foundation
import Security

/// An opaque identifier, not health data or a provider credential. Keep it in a
/// separate, nonsynchronizing ThisDeviceOnly item so account credential erasure
/// cannot orphan a previously requested Health deletion. Never adopt the owner
/// found in an imported file when this key is absent.
enum HealthWriteDeviceOwner {
    private static let service = "com.dbakp.lumen.health-intent-owner"
    private static let account = "owner.v1"
    private static let lock = NSLock()
    struct Failure: Error { let status: OSStatus }

    static func current() throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        if let owner = try read() { return owner }
        let owner = UUID()
        var item = query
        item[kSecValueData as String] = Data(owner.uuidString.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure(status: status) }
        guard let saved = try read() else { throw Failure(status: errSecItemNotFound) }
        return saved
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    private static func read() throws -> UUID? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecReturnAttributes as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure(status: status) }
        guard let attributes = result as? [String: Any],
              attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
              (attributes[kSecAttrSynchronizable as String] as? Bool) != true,
              let data = attributes[kSecValueData as String] as? Data,
              let text = String(data: data, encoding: .utf8), text.utf8.count == 36,
              let value = UUID(uuidString: text) else { throw Failure(status: errSecDecode) }
        return value
    }
}
