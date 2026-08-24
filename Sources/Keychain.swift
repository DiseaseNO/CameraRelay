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
        let status = SecItemAdd(spørring as CFDictionary, nil)
        #if DEBUG
        // Simulator-bygget i CI er USIGNERT (CODE_SIGNING_ALLOWED=NO) og har derfor ingen
        // keychain-entitlement. SecItemAdd feiler da med -34018, og verdien forsvant i
        // stillhet. For at skjermbilde-testene skal komme forbi paringen faller vi tilbake
        // på UserDefaults. Release-bygg — det du installerer — har ikke denne koden.
        if status != errSecSuccess {
            NSLog("CR-KEYCHAIN: SecItemAdd feilet (\(status)) — bruker UserDefaults i DEBUG")
            UserDefaults.standard.set(verdi, forKey: reservenøkkel(konto))
        }
        #else
        _ = status
        #endif
    }

    #if DEBUG
    private static func reservenøkkel(_ konto: String) -> String { "nk_" + konto }
    #endif

    static func les(_ konto: String) -> String? {
        let spørring: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjeneste,
            kSecAttrAccount as String: konto,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ut: CFTypeRef?
        if SecItemCopyMatching(spørring as CFDictionary, &ut) == errSecSuccess,
           let data = ut as? Data {
            return String(data: data, encoding: .utf8)
        }
        #if DEBUG
        return UserDefaults.standard.string(forKey: reservenøkkel(konto))
        #else
        return nil
        #endif
    }

    static func slett(_ konto: String) {
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: reservenøkkel(konto))
        #endif
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: tjeneste,
            kSecAttrAccount as String: konto,
        ] as CFDictionary)
    }
}
