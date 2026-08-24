import Foundation
import Observation

// Datamodellene speiler backend (`/api/kamera/tidslinje`). Recorderen deler opptak i to
// slag under type 131072: subtype 1 = kontinuerlig råopptak, subtype 2 = deteksjonsklipp
// (ett per bevegelse). Type 2 er selve motion-alarmen. Se smarthus/docs/kamera-relay.md.
struct Intervall: Decodable, Hashable {
    let s: String, e: String
    let sUnix: Double, eUnix: Double
    var start: Date { Date(timeIntervalSince1970: sUnix) }
    var slutt: Date { Date(timeIntervalSince1970: eUnix) }
    var lengde: TimeInterval { max(0, eUnix - sUnix) }
}
struct Hendelse: Decodable, Hashable {
    let type: Int, subtype: Int
    let intervaller: [Intervall]
}
struct KameraTL: Decodable, Hashable {
    let navn: String
    let hendelser: [Hendelse]

    var deteksjonsklipp: [Intervall] {
        hendelser.filter { $0.type == 131072 && $0.subtype == 2 }
            .flatMap(\.intervaller).sorted { $0.sUnix < $1.sUnix }
    }
    var kontinuerlig: [Intervall] {
        hendelser.filter { $0.type == 131072 && $0.subtype == 1 }.flatMap(\.intervaller)
    }
    var alarmer: [Intervall] {
        hendelser.filter { $0.type == 2 }.flatMap(\.intervaller).sorted { $0.sUnix < $1.sUnix }
    }
    /// Motion-alarmen som ligger inni klippet — recorderen indekserer film-stripene på
    /// ALARM-tidspunktet, ikke på klippets start (klippet begynner 10 s før).
    func alarm(i klipp: Intervall) -> Intervall? {
        alarmer.first { $0.sUnix >= klipp.sUnix - 2 && $0.sUnix <= klipp.eUnix + 2 }
    }
}
struct Tidslinje: Decodable { let kameraer: [KameraTL] }

struct ParSvar: Decodable {
    let token: String
    struct Enhet: Decodable { let id: String; let navn: String }
    let enhet: Enhet
}

enum APIFeil: LocalizedError {
    case ingenServer, ikkeAutorisert, kode(Int), nettverk(String)
    var errorDescription: String? {
        switch self {
        case .ingenServer:     "Ingen server satt opp."
        case .ikkeAutorisert:  "Enheten er ikke lenger godkjent. Par på nytt."
        case .kode(let n):     "Serveren svarte \(n)."
        case .nettverk(let m): m
        }
    }
}

/// Klienten mot smarthus-backend. Appen kjenner ingen adresser på forhånd — verten
/// skrives inn ved paring og lagres i Keychain sammen med enhets-tokenet.
@Observable
final class API {
    private(set) var vert: String? = Nøkkelring.les("vert")
    private(set) var token: String? = Nøkkelring.les("token")
    var erKlar: Bool { vert != nil && token != nil }

    init() {
        #if DEBUG
        NSLog("CR-API: vert=\(vert ?? "nil") token=\(token != nil ? "ok" : "nil") erKlar=\(erKlar)")
        #endif
    }

    // MARK: paring

    /// Løser inn en paringskode fra dashbordet. Passordet ditt kommer aldri inn i appen —
    /// koden er engangs og lever i 5 minutter.
    func par(vert: String, kode: String, enhetsnavn: String) async throws {
        let renVert = vert.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "https://\(renVert)/api/enheter/par") else { throw APIFeil.ingenServer }
        var rq = URLRequest(url: url)
        rq.httpMethod = "POST"
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        rq.httpBody = try JSONEncoder().encode(["kode": kode, "navn": enhetsnavn])
        let (data, svar) = try await URLSession.shared.data(for: rq)
        guard let h = svar as? HTTPURLResponse else { throw APIFeil.nettverk("Uventet svar") }
        guard h.statusCode == 200 else {
            throw h.statusCode == 401 ? APIFeil.nettverk("Ugyldig eller utløpt kode.") : APIFeil.kode(h.statusCode)
        }
        let p = try JSONDecoder().decode(ParSvar.self, from: data)
        Nøkkelring.skriv(renVert, for: "vert")
        Nøkkelring.skriv(p.token, for: "token")
        self.vert = renVert
        self.token = p.token
    }

    func glemEnhet() {
        Nøkkelring.slett("vert"); Nøkkelring.slett("token")
        vert = nil; token = nil
    }

    // MARK: data

    func tidslinje() async throws -> [KameraTL] {
        try await hent(Tidslinje.self, "/api/kamera/tidslinje").kameraer
    }

    /// Film-stripa recorderen lager per hendelse: fire rammer i én JPEG (~1456x200).
    /// Vises i sin helhet — beskjæres den til 16:9 ser man bare en stripe av hendelsen.
    func stripeURL(kamera: String, alarmUnix: Double) -> URL? {
        url("/api/kamera/\(kod(kamera))/bilde", ["t": String(Int(alarmUnix)), "sub": "2"])
    }

    /// HLS. AVPlayer kan ikke MSE, så backend pakker den samme fMP4-strømmen som
    /// EXT-X-MAP + EXT-X-BYTERANGE. Ingen transkoding — samme byte-ranges som web-spilleren.
    func liveURL(kamera: String) -> URL? {
        url("/api/kamera/\(kod(kamera))/live.m3u8", [:])
    }
    func opptakURL(kamera: String, klipp: Intervall, sub: Int = 2) -> URL? {
        url("/api/kamera/\(kod(kamera))/opptak.m3u8", ["s": klipp.s, "e": klipp.e, "sub": String(sub)])
    }

    /// AVURLAsset kan ikke sette Authorization-header selv, så tokenet må følge med i
    /// spørrestrengen for medie-URL-ene. Backend godtar begge.
    private func url(_ sti: String, _ q: [String: String]) -> URL? {
        guard let vert, let token else { return nil }
        var c = URLComponents(string: grunnadresse(vert)) ?? URLComponents()
        c.percentEncodedPath = sti   // kameranavnet er allerede kodet av kod()
        var deler = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        deler.append(URLQueryItem(name: "token", value: token))
        c.queryItems = deler
        return c.url
    }
    /// Alltid https. Backend har ekte sertifikat, så det finnes ingen grunn til unntak.
    private func grunnadresse(_ vert: String) -> String { "https://" + vert }

    private func kod(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func hent<T: Decodable>(_ type: T.Type, _ sti: String) async throws -> T {
        guard let vert, let token, let u = URL(string: grunnadresse(vert) + sti) else { throw APIFeil.ingenServer }
        var rq = URLRequest(url: u)
        rq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        rq.timeoutInterval = 30
        let (data, svar) = try await URLSession.shared.data(for: rq)
        guard let h = svar as? HTTPURLResponse else { throw APIFeil.nettverk("Uventet svar") }
        if h.statusCode == 401 { throw APIFeil.ikkeAutorisert }
        guard h.statusCode == 200 else { throw APIFeil.kode(h.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
