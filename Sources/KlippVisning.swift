import SwiftUI

/// Opptak: tidslinje øverst, klippene i det synlige vinduet under.
///
/// Vinduet ER utvalget — panorerer du bakover, følger lista med. Det er samme grep som på
/// vegg-dashbordet, og på mobil er det ekstra nyttig: du slipper et eget filtervalg.
struct KlippVisning: View {
    let api: API

    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var laster = true
    @State private var vindu = Tidslinje.Vindu(slutt: .now, spenn: 3 * 3600)
    @State private var valgt: IntPakke?

    /// Alle klipp i vinduet, nyest først — dette er også rekkefølgen spilleren blar i.
    private var iVinduet: [Klipp] {
        kameraer.flatMap { kam in
            kam.deteksjonsklipp
                .filter { $0.slutt >= vindu.fra && $0.start <= vindu.slutt }
                .map { Klipp(kamera: kam.navn, iv: $0, alarm: kam.alarm(i: $0)) }
        }
        .sorted { $0.iv.sUnix > $1.iv.sUnix }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                if laster {
                    ProgressView().tint(Farge.dempet)
                } else if let feil {
                    VStack(spacing: 8) {
                        Text(feil).foregroundStyle(Farge.avvik)
                        Button("Prøv igjen") { Task { await last() } }
                            .foregroundStyle(Farge.aksent)
                    }
                } else {
                    innhold
                }
            }
            .navigationTitle("Opptak")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .fullScreenCover(item: $valgt) { pakke in
                SpillerSkjerm(api: api, klipp: iVinduet, start: pakke.verdi)
            }
        }
        .task { await last() }
    }

    private var innhold: some View {
        VStack(spacing: 0) {
            Tidslinje(kameraer: kameraer, vindu: $vindu) { kamera, iv in
                // Trykk i tidslinja åpner klippet direkte — ingen omvei via lista.
                if let i = iVinduet.firstIndex(where: { $0.kamera == kamera && $0.iv.sUnix == iv.sUnix }) {
                    valgt = IntPakke(verdi: i)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().overlay(Farge.strek)

            if iVinduet.isEmpty {
                Spacer()
                Text("Ingen klipp i dette tidsrommet.")
                    .font(.subheadline).foregroundStyle(Farge.svak)
                Spacer()
            } else {
                List(Array(iVinduet.enumerated()), id: \.element.id) { i, k in
                    Button { valgt = IntPakke(verdi: i) } label: { rad(k) }
                        .listRowBackground(Farge.kort)
                        .listRowSeparatorTint(Farge.strek)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await last() }
            }
        }
    }

    private func rad(_ k: Klipp) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Farge.aksent).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(k.iv.start, format: .dateTime.hour().minute().second())
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Farge.tekst)
                Text(k.kamera).font(.caption).foregroundStyle(Farge.dempet)
            }
            .frame(width: 78, alignment: .leading)

            Stripe(api: api, klipp: k).frame(height: 38)

            Text(varighet(k.iv))
                .font(.caption.monospacedDigit()).foregroundStyle(Farge.svak)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func varighet(_ iv: Intervall) -> String {
        let d = Int(iv.lengde.rounded())
        return d < 60 ? "\(d)s" : "\(d / 60)m \(d % 60)s"
    }

    private func last() async {
        laster = kameraer.isEmpty
        defer { laster = false }
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { feil = error.localizedDescription }
    }
}

// MARK: - byggeklosser

struct Klipp: Identifiable {
    let kamera: String
    let iv: Intervall
    let alarm: Intervall?
    var id: String { "\(kamera)-\(Int(iv.sUnix))" }

    /// Alarmvinduet i sekunder fra klippets start — det gule feltet i spillerens bar.
    var markering: (fra: Double, til: Double)? {
        guard let a = alarm else { return nil }
        let fra = max(0, a.sUnix - iv.sUnix)
        return (fra, max(fra + 1, a.eUnix - iv.sUnix))
    }
}

/// Recorderens film-stripe: fire rammer i én JPEG. Vises HEL — beskjærer man den til
/// 16:9 ser man bare en flis av hendelsen, og da er den verdiløs.
struct Stripe: View {
    let api: API
    let klipp: Klipp

    var body: some View {
        AsyncImage(url: api.stripeURL(kamera: klipp.kamera,
                                      alarmUnix: (klipp.alarm ?? klipp.iv).sUnix)) { faser in
            switch faser {
            case .success(let bilde):
                bilde.resizable().scaledToFit()
            default:
                RoundedRectangle(cornerRadius: 4).fill(Farge.kort2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

/// Liten innpakning så en indeks kan brukes med `.fullScreenCover(item:)`.
struct IntPakke: Identifiable {
    let verdi: Int
    var id: Int { verdi }
}
