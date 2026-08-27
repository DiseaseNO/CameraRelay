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
/// Svaret fra /api/kamera/tidslinje. Heter ikke bare «Tidslinje» fordi visningen
/// med samme navn ville kollidert.
struct TidslinjeSvar: Decodable { let kameraer: [KameraTL] }

/// Et LÅST opptak, slik recorderen selv rapporterer det (`/api/kamera/laste`).
///
/// Grensene her er recorderens egne, og de kan avvike litt fra dem vi har lagret —
/// recorderen justerer et deteksjonsklipp mens bevegelsen pågår. Derfor sammenlignes
/// låste klipp med OVERLAPP, ikke med likhet.
struct LåstKlipp: Decodable, Hashable, Identifiable {
    let navn: String, sub: Int
    let s: String, e: String
    let sUnix: Double, eUnix: Double
    var id: String { "\(navn)-\(Int(sUnix))" }
    var intervall: Intervall { Intervall(s: s, e: e, sUnix: sUnix, eUnix: eUnix) }
    var start: Date { Date(timeIntervalSince1970: sUnix) }
    var lengde: TimeInterval { max(0, eUnix - sUnix) }
}
private struct LåsteSvar: Decodable { let klipp: [LåstKlipp] }

// MARK: driftsstatus

/// En systemd-tjeneste på serveren (CT 115).
struct TjenesteStatus: Decodable, Identifiable, Hashable {
    let navn: String, unit: String, hva: String
    let aktiv: Bool, tilstand: String
    let oppeSek: Double, minneMB: Int
    var id: String { unit }
}
/// Recorderens ressursbruk. Ikke sanntid — backend cacher i et minutt, for hvert
/// oppslag koster recorderen noe.
struct RecorderStatus: Decodable, Hashable {
    struct Disk: Decodable, Hashable { let brukt: Double; let total: Double; let prosent: Double }
    struct Logg: Decodable, Hashable { let prosent: Double }
    let cpu: Double, minne: Double, last: Double
    let sesjoner: Int
    let videodisk: Disk
    let loggdisk: Logg
    let oppetid: String, firmware: String, serienummer: String
    /// Recorderens EGET anslag for hvor lenge til videodisken er full (sekunder).
    let estimertLagring: Double
    /// Hvor langt tilbake den faktisk har opptak nå (sekunder).
    let faktiskLagring: Double
}
struct DriftSvar: Decodable {
    let tjenester: [TjenesteStatus]
    let recorder: RecorderStatus?
    let recorderFeil: String?
    let tid: Double
}
private struct LåsSvar: Decodable { let laast: Bool }

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
    /// Delt referanse, så små visninger slipper å få API sendt gjennom flere ledd.
    static private(set) var delt: API?

    private(set) var vert: String? = Nøkkelring.les("vert")
    private(set) var token: String? = Nøkkelring.les("token")
    var erKlar: Bool { vert != nil && token != nil }

    init() {
        API.delt = self
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
        try await hent(TidslinjeSvar.self, "/api/kamera/tidslinje").kameraer
    }

    /// Driftsstatus: tjenestene på serveren + recorderens ressursbruk.
    ///
    /// Stien ligger under `/api/kamera/` med vilje. Utenfra går appen gjennom
    /// `frcr.gustavs1.no`, der FortiADC bare slipper gjennom `^/api/kamera/`,
    /// `/api/enheter/par` og `/api/health` — alt annet dropper med **503**. Det var
    /// nettopp det som skjedde da endepunktet het `/api/system/status`.
    func drift() async throws -> DriftSvar {
        try await hent(DriftSvar.self, "/api/kamera/drift")
    }

    // MARK: låsing

    /// Alle låste opptak, nyest først. Recorderen filtrerer selv, så dette er ETT kall —
    /// vi spør aldri om låsestatus per klipp mens man blar (det ville fått recorderen til
    /// å generere et klipp for hver rad man rullet forbi).
    func låsteKlipp() async throws -> [LåstKlipp] {
        try await hent(LåsteSvar.self, "/api/kamera/laste", ["dager": "365"]).klipp
    }

    /// Låser eller låser opp et klipp. Låste opptak overlever recorderens opprydding
    /// når disken går full — det er hele poenget med knappen.
    @discardableResult
    func settLås(kamera: String, klipp: Intervall, sub: Int = 2, lås: Bool) async throws -> Bool {
        try await send(LåsSvar.self, "/api/kamera/\(kod(kamera))/las",
                       ["s": klipp.s, "e": klipp.e, "sub": String(sub), "las": lås ? "1" : "0"]).laast
    }

    // MARK: nedlasting

    /// Laster klippet ned til en midlertidig fil og gir tilbake stien.
    ///
    /// Backend pakker om til vanlig progressiv MP4 med `hvc1`-tag; recorderens egen fil er
    /// fragmentert og tagget `hev1`, som verken Fotos eller AVFoundation vil ha.
    /// `download` skriver rett til disk — et 4K-klipp er titalls MB og har ingenting i
    /// minnet å gjøre.
    func lastNedKlipp(kamera: String, klipp: Intervall, sub: Int = 2) async throws -> URL {
        guard let u = adresse("/api/kamera/\(kod(kamera))/nedlasting.mp4",
                              ["s": klipp.s, "e": klipp.e, "sub": String(sub)]) else { throw APIFeil.ingenServer }
        var rq = URLRequest(url: u)
        rq.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        rq.timeoutInterval = 180
        let (fil, svar) = try await URLSession.shared.download(for: rq)
        guard let h = svar as? HTTPURLResponse else { throw APIFeil.nettverk("Uventet svar") }
        if h.statusCode == 401 { throw APIFeil.ikkeAutorisert }
        guard h.statusCode == 200 else { throw APIFeil.kode(h.statusCode) }
        // URLSession gir fila et navn uten etternavn. Fotos leser typen fra endelsen, så
        // uten «.mp4» blir importen avvist.
        let mål = FileManager.default.temporaryDirectory
            .appendingPathComponent(navnFra(h) ?? "\(kamera)-\(Int(klipp.sUnix)).mp4")
        try? FileManager.default.removeItem(at: mål)
        try FileManager.default.moveItem(at: fil, to: mål)
        return mål
    }

    /// Filnavnet backend foreslår i Content-Disposition («Gate-2026-08-27-21_50_05.mp4»).
    private func navnFra(_ h: HTTPURLResponse) -> String? {
        guard let cd = h.value(forHTTPHeaderField: "Content-Disposition"),
              let m = cd.range(of: "filename=\"") else { return nil }
        let rest = cd[m.upperBound...]
        guard let slutt = rest.firstIndex(of: "\"") else { return nil }
        let navn = String(rest[..<slutt])
        return navn.contains("/") || navn.isEmpty ? nil : navn
    }

    /// Film-stripa recorderen lager per hendelse: fire rammer i én JPEG (~1456x200).
    /// Vises i sin helhet — beskjæres den til 16:9 ser man bare en stripe av hendelsen.
    func stripeURL(kamera: String, alarmUnix: Double) -> URL? {
        url("/api/kamera/\(kod(kamera))/bilde", ["t": String(Int(alarmUnix)), "sub": "2"])
    }

    /// HLS. AVPlayer kan ikke MSE, så backend pakker den samme fMP4-strømmen som
    /// EXT-X-MAP + EXT-X-BYTERANGE. Ingen transkoding — samme byte-ranges som web-spilleren.
    /// EKTE 4K live. Backend henter recorderens RTSP-strøm (3840x2160 HEVC) og pakker den
    /// om til HLS uten å re-enkode. Live-relayen gir 720p fordi den ber recorderen
    /// transkode for nettleser; denne går utenom det.
    func live4kURL(kamera: String) -> URL? {
        url("/api/kamera/\(kod(kamera))/live4k.m3u8", [:])
    }

    func liveURL(kamera: String) -> URL? {
        url("/api/kamera/\(kod(kamera))/live.m3u8", [:])
    }
    /// Fri spoling: recorderen klipper et VILKÅRLIG tidsrom, ikke bare ferdige hendelser.
    /// Backend tar `?alarm=<unix>` og lager et vindu på −10/+30 s rundt tidspunktet, så vi
    /// forskyver 10 s fram for å starte omtrent der markøren står.
    func friOpptakURL(kamera: String, fra: Date) -> URL? {
        // sub=1 = KONTINUERLIG opptak. Det er den grønne linja man spoler i; ber man om
        // sub=2 (deteksjon) på et punkt uten hendelse, svarer recorderen tomt — og da
        // kommer det ingen video.
        url("/api/kamera/\(kod(kamera))/opptak.m3u8",
            ["alarm": String(Int(fra.timeIntervalSince1970) + 10), "sub": "1"])
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

    /// Adresse UTEN token i spørrestrengen — til kall som kan sette Authorization-header
    /// selv. Bare medie-URL-ene (`url`) trenger tokenet i klartekst.
    private func adresse(_ sti: String, _ q: [String: String] = [:]) -> URL? {
        guard let vert else { return nil }
        var c = URLComponents(string: grunnadresse(vert)) ?? URLComponents()
        c.percentEncodedPath = sti
        if !q.isEmpty { c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return c.url
    }

    private func hent<T: Decodable>(_ type: T.Type, _ sti: String, _ q: [String: String] = [:]) async throws -> T {
        try await kall(type, sti, q, metode: "GET")
    }
    private func send<T: Decodable>(_ type: T.Type, _ sti: String, _ q: [String: String] = [:]) async throws -> T {
        try await kall(type, sti, q, metode: "POST")
    }

    private func kall<T: Decodable>(_ type: T.Type, _ sti: String, _ q: [String: String], metode: String) async throws -> T {
        guard let token, let u = adresse(sti, q) else { throw APIFeil.ingenServer }
        var rq = URLRequest(url: u)
        rq.httpMethod = metode
        rq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        rq.timeoutInterval = 60
        let (data, svar) = try await URLSession.shared.data(for: rq)
        guard let h = svar as? HTTPURLResponse else { throw APIFeil.nettverk("Uventet svar") }
        if h.statusCode == 401 { throw APIFeil.ikkeAutorisert }
        guard h.statusCode == 200 else { throw APIFeil.kode(h.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// En avbrutt forespørsel er ikke en feil.
///
/// SwiftUIs `.task` kansellerer det som er underveis når visningen forsvinner — bytter du
/// fane mens tidslinja lastes, får vi `NSURLErrorCancelled` (-999). Å vise «cancelled» i
/// rødt får en helt normal hendelse til å se ut som at noe er ødelagt.
func erAvbrutt(_ feil: Error) -> Bool {
    if feil is CancellationError { return true }
    let n = feil as NSError
    return n.domain == NSURLErrorDomain && n.code == NSURLErrorCancelled
}
