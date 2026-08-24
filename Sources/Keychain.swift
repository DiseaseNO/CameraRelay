import Foundation
import Security

/// Enhets-tokenet og serveradressen hører hjemme i Keychain, ikke i UserDefaults.
/// `kSecAttrAccessibleAfterFirstUnlock` gjør at appen kan hente strømmen i bakgrunnen
/// etter at telefonen er låst opp én gang siden oppstart.
enum Nøkkelring {
    private static let tjeneste = "no.gustavs1.camerarelay"

    static func skriv(_ verdi: String, for konto: String) {
        slett(konto)
        let spørring: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjeneste,
            kSecAttrAccount as String: konto,
            kSecValueData as String: Data(verdi.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(spørring as CFDictionary, nil)
    }

    static func les(_ konto: String) -> String? {
        let spørring: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjeneste,
            kSecAttrAccount as String: konto,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ut: CFTypeRef?
        guard SecItemCopyMatching(spørring as CFDictionary, &ut) == errSecSuccess,
              let data = ut as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func slett(_ konto: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjeneste,
            kSecAttrAccount as String: konto,
        ] as CFDictionary)
    }
}
