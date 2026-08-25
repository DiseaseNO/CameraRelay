import SwiftUI
import UIKit

/// Mellomlager og forhåndshenting av film-striper.
///
/// `AsyncImage` henter først når raden dukker opp på skjermen, og da ser man den bli til.
/// Her henter vi et stykke UTENFOR det synlige i begge retninger, så lista føles ferdig
/// lastet uansett hvilken vei man ruller.
///
/// Vi henter ikke alt: med flere hundre hendelser ville det vært mange megabyte og en
/// unødvendig kø mot recorderen. Et vindu rundt det synlige gir samme opplevelse til en
/// brøkdel av trafikken.
///
/// IKKE @Observable. Den var det, og det ga hakkete rulling: hver ferdig nedlasting skrev
/// til en observert teller, og SwiftUI ugyldiggjorde visninger midt i rullingen. `pågår` ble
/// i tillegg endret fra en bakgrunnskø — å skrive til observert tilstand utenfor hovedtråden
/// er direkte ulovlig. Tellerne leses nå bare når Innstillinger åpnes.
final class Bildelager {
    static let delt = Bildelager()

    private let lager = NSCache<NSURL, UIImage>()
    /// Beskyttet av `låsen` — den berøres fra nettverkstråder.
    private var pågår = Set<URL>()
    private let låsen = NSLock()

    /// Antall hentede bilder — vises under Innstillinger.
    private(set) var antallHentet = 0
    private(set) var bytesHentet = 0
    private(set) var antallFeilet = 0

    /// Fire forsøk med 1, 2 og 4 sekunders pause. Recorderen genererer stripene på
    /// forespørsel, og en fersk hendelse kan rett og slett ikke være klar ennå — da hjelper
    /// det å spørre igjen om noen sekunder framfor å la ruta stå tom for alltid.
    private let maksForsøk = 4

    init() {
        lager.countLimit = 400          // ~400 striper er rikelig for en dag
        lager.totalCostLimit = 64 << 20 // 64 MB
    }

    func bilde(_ url: URL) -> UIImage? { lager.object(forKey: url as NSURL) }

    /// Henter hvis vi ikke har den fra før. Trygg å kalle mange ganger.
    ///
    /// `ferdig` kalles på hovedtråden, og bare ÉN gang: enten med bildet, eller med nil når
    /// alle forsøk er brukt opp.
    func hent(_ url: URL, ferdig: ((UIImage?) -> Void)? = nil) {
        if let b = bilde(url) { ferdig?(b); return }

        låsen.lock()
        let alleredeIGang = pågår.contains(url)
        if !alleredeIGang { pågår.insert(url) }
        låsen.unlock()
        // Er den allerede underveis, får den som ba først svaret. Å starte en runde til
        // ville bare doblet trafikken mot recorderen.
        guard !alleredeIGang else { return }

        forsøk(url, nr: 0, ferdig: ferdig)
    }

    /// Ett forsøk. Ved feil venter vi og prøver igjen — `pågår` holdes gjennom HELE kjeden,
    /// så en rad som ruller forbi ikke starter en parallell runde.
    private func forsøk(_ url: URL, nr: Int, ferdig: ((UIImage?) -> Void)?) {
        var rq = URLRequest(url: url)
        // Standard er 60 s. Så lenge vil ingen vente på en miniatyr — da er det bedre å
        // gi opp raskt og prøve på nytt.
        rq.timeoutInterval = 15

        URLSession.shared.dataTask(with: rq) { [weak self] data, svar, _ in
            guard let self else { return }
            let kode = (svar as? HTTPURLResponse)?.statusCode ?? 0

            if kode == 200, let data, let b = UIImage(data: data) {
                self.lager.setObject(b, forKey: url as NSURL, cost: data.count)
                self.låsen.lock()
                self.pågår.remove(url)
                self.antallHentet += 1
                self.bytesHentet += data.count
                self.låsen.unlock()
                // Bare visningen som VENTER på nettopp dette bildet vekkes. Ingen global
                // ugyldiggjøring — det var det som lugget.
                if let ferdig { DispatchQueue.main.async { ferdig(b) } }
                return
            }

            // 401 kommer av et utløpt token og blir ikke bedre av å prøve igjen.
            let nytteløst = kode == 401 || kode == 403
            guard !nytteløst, nr + 1 < self.maksForsøk else {
                self.låsen.lock(); self.pågår.remove(url); self.antallFeilet += 1; self.låsen.unlock()
                if let ferdig { DispatchQueue.main.async { ferdig(nil) } }
                return
            }

            let pause = pow(2.0, Double(nr))   // 1 s, 2 s, 4 s
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + pause) {
                self.forsøk(url, nr: nr + 1, ferdig: ferdig)
            }
        }.resume()
    }

    /// Forhåndshenter et vindu rundt det synlige.
    func forhåndshent(_ urler: [URL]) {
        for u in urler where bilde(u) == nil { hent(u) }
    }

    func tøm() {
        lager.removeAllObjects()
        låsen.lock(); antallHentet = 0; bytesHentet = 0; antallFeilet = 0; låsen.unlock()
    }
}

/// Bilde fra mellomlageret. Viser en dempet flate til det er hentet — ingen hopp i layout,
/// fordi rammen har fast sideforhold uansett.
///
/// Gir seg ikke etter et mislykket forsøk: `Bildelager` prøver fire ganger av seg selv, og
/// blir det likevel ingenting, får man en knapp å trykke på. En tom rute uten forklaring
/// ser ut som en ødelagt app.
struct Mellomlagret: View {
    let url: URL?
    var fyll = false

    @State private var bilde: UIImage?
    @State private var mislyktes = false

    var body: some View {
        Group {
            if let bilde {
                Image(uiImage: bilde).resizable()
                    .aspectRatio(contentMode: fyll ? .fill : .fit)
            } else if mislyktes {
                ZStack {
                    Rectangle().fill(Farge.kort2)
                    Button { last(påNytt: true) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise").font(.caption)
                            Text("prøv igjen").font(.system(size: 9))
                        }
                        .foregroundStyle(Farge.dempet)
                    }
                }
            } else {
                Rectangle().fill(Farge.kort2)
            }
        }
        .onAppear { last() }
        // Ruller man forbi og tilbake igjen, er det et nytt forsøk verdt — det kan ha vært
        // et blaff i nettet, eller recorderen kan ha blitt ferdig med stripa i mellomtiden.
        .onChange(of: url) { _, _ in bilde = nil; mislyktes = false; last() }
    }

    private func last(påNytt: Bool = false) {
        guard let url else { return }
        if let b = Bildelager.delt.bilde(url) { bilde = b; return }
        if påNytt { mislyktes = false }
        Bildelager.delt.hent(url) { b in
            if let b { bilde = b; mislyktes = false } else { mislyktes = true }
        }
    }
}
