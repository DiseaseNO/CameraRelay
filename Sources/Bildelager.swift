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

    init() {
        lager.countLimit = 400          // ~400 striper er rikelig for en dag
        lager.totalCostLimit = 64 << 20 // 64 MB
    }

    func bilde(_ url: URL) -> UIImage? { lager.object(forKey: url as NSURL) }

    /// Henter hvis vi ikke har den fra før. Trygg å kalle mange ganger.
    func hent(_ url: URL, ferdig: ((UIImage?) -> Void)? = nil) {
        if let b = bilde(url) { ferdig?(b); return }

        låsen.lock()
        let alleredeIGang = pågår.contains(url)
        if !alleredeIGang { pågår.insert(url) }
        låsen.unlock()
        guard !alleredeIGang else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            self.låsen.lock(); self.pågår.remove(url); self.låsen.unlock()

            guard let data, let b = UIImage(data: data) else {
                if let ferdig { DispatchQueue.main.async { ferdig(nil) } }
                return
            }
            self.lager.setObject(b, forKey: url as NSURL, cost: data.count)
            self.låsen.lock(); self.antallHentet += 1; self.bytesHentet += data.count; self.låsen.unlock()
            // Bare visninger som VENTER på nettopp dette bildet vekkes. Ingen global
            // ugyldiggjøring — det var det som lugget.
            if let ferdig { DispatchQueue.main.async { ferdig(b) } }
        }.resume()
    }

    /// Forhåndshenter et vindu rundt det synlige.
    func forhåndshent(_ urler: [URL]) {
        for u in urler where bilde(u) == nil { hent(u) }
    }

    func tøm() {
        lager.removeAllObjects()
        låsen.lock(); antallHentet = 0; bytesHentet = 0; låsen.unlock()
    }
}

/// Bilde fra mellomlageret. Viser en dempet flate til det er hentet — ingen hopp i layout,
/// fordi rammen har fast sideforhold uansett.
struct Mellomlagret: View {
    let url: URL?
    var fyll = false

    @State private var bilde: UIImage?

    var body: some View {
        Group {
            if let bilde {
                Image(uiImage: bilde).resizable()
                    .aspectRatio(contentMode: fyll ? .fill : .fit)
            } else {
                Rectangle().fill(Farge.kort2)
            }
        }
        .onAppear { last() }
        .onChange(of: url) { _, _ in bilde = nil; last() }
    }

    private func last() {
        guard let url else { return }
        if let b = Bildelager.delt.bilde(url) { bilde = b; return }
        Bildelager.delt.hent(url) { b in if b != nil { bilde = b } }
    }
}
