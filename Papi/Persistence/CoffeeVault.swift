import Foundation
import Security

/// One atomic, read-back-verified snapshot for local identity, wallet and journal mutations.
/// Media bytes live separately; only relative media names are persisted here.
enum CoffeeVault {
    static let service = "Papi.LocalGuest.v1"
    static let account = "local-state"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    private static var snapshotMarker:URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("CoffeeArchive",isDirectory:true).appendingPathComponent("snapshot.saved")
    }
    private static func rememberSnapshot() throws {
        guard !FileManager.default.fileExists(atPath:snapshotMarker.path) else{return}
        try FileManager.default.createDirectory(at:snapshotMarker.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data(service.utf8).write(to:snapshotMarker,options:.atomic)
    }
    static func read() throws -> CoffeeArchive? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound {
            guard !FileManager.default.fileExists(atPath:snapshotMarker.path) else{throw VaultError.missingSnapshot}
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.access(status) }
        let saved=try JSONDecoder().decode(CoffeeArchive.self,from:data)
        try rememberSnapshot()
        return saved
    }
    static func write(_ state: CoffeeArchive) throws {
        let data = try JSONEncoder().encode(state)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw VaultError.access(status) }
        // An existence marker survives relaunch without copying identity, messages or wallet data.
        do {try rememberSnapshot()} catch {throw VaultError.verification}
        var q = query; q[kSecReturnData as String] = true
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(q as CFDictionary, &result)
        guard readStatus == errSecSuccess, let saved = result as? Data, saved == data else { throw VaultError.verification }
    }
    enum VaultError: LocalizedError {
        case access(OSStatus), verification, missingSnapshot
        var errorDescription: String? {
            switch self {
            case .missingSnapshot:return "Your saved coffee account could not be found. Local changes are paused to protect your balance. Please try again later."
            case .access,.verification:return "Your local data could not be verified. Unlock this device and retry local storage before making more changes."
            }
        }
    }
}
