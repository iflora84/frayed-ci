import Foundation
import Security

enum AgeStatus {
    case unknown, adult, blocked
}

/// The 16+ gate (SPEC 1.6, AgePolicy). A pass is kept in UserDefaults. A
/// block is kept twice: in the Keychain, which survives deleting the app,
/// and in UserDefaults, which covers relaunches if the Keychain write or
/// read fails. Either copy blocks. The full birth date is never stored; a
/// pass keeps only the year, in the Keychain next to the block.
enum AgeCheck {
    private static let adultKey = "agegate.adult"
    private static let blockedKey = "agegate.blocked"
    private static let service = "com.iflora.frayed.agegate"
    private static let blockedAccount = "blocked"
    private static let birthYearAccount = "birthYear"

    static func current() -> AgeStatus {
        if isBlocked {
            return .blocked
        }
        return UserDefaults.standard.bool(forKey: adultKey) ? .adult : .unknown
    }

    static func pass(birthYear: Int) -> AgeStatus {
        UserDefaults.standard.set(true, forKey: adultKey)
        write(String(birthYear), account: birthYearAccount)
        return .adult
    }

    static func block() -> AgeStatus {
        UserDefaults.standard.set(false, forKey: adultKey)
        UserDefaults.standard.set(true, forKey: blockedKey)
        write("1", account: blockedAccount)
        return .blocked
    }

    /// The year recorded at the gate, nil before it was passed.
    static var birthYear: Int? {
        return read(account: birthYearAccount).flatMap { Int($0) }
    }

    private static func query(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static var isBlocked: Bool {
        if UserDefaults.standard.bool(forKey: blockedKey) {
            return true
        }
        guard read(account: blockedAccount) != nil else {
            return false
        }
        // A reinstall: bring the UserDefaults copy back too.
        UserDefaults.standard.set(true, forKey: blockedKey)
        return true
    }

    private static func read(account: String) -> String? {
        var query = self.query(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(item as CFDictionary, nil) == errSecDuplicateItem {
            let changes: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(query(account: account) as CFDictionary, changes as CFDictionary)
        }
    }
}
