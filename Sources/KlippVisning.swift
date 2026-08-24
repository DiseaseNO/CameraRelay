import SwiftUI

/// Opptak: liste over deteksjonsklipp med recorderens film-stripe, nyeste først.
/// Samme oppsett som kamerafanen i dashbordet — tid, kamera, stripe, varighet.
struct KlippVisning: View {
    let api: API
    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var laster = true

    private struct Rad: Identifiable {
        let id = UUID()
        let kamera: String
        let klipp: Intervall
        let alarm: Intervall?
    }

    private var rader: [Rad] {
        kameraer.flatMap { kam in
            kam.deteksjonsklipp.map { Rad(kamera: kam.navn, klipp: $0, alarm: kam.alarm(i: $0)) }
        }
        .sorted { $0.klipp.sUnix > $1.klipp.sUnix }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                if laster {
                    ProgressView().tint(Farge.dempet)
                } else if let feil {
                    Text(feil).foregroundStyle(Farge.avvik).padding()
                } else {
                    List(rader) { rad in
                        NavigationLink {
                            klippSkjerm(rad)
                        } label: {
                            radInnhold(rad)
                        }
                        .listRowBackground(Farge.kort)
                        .listRowSeparatorTint(Farge.strek)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await last() }
                }
            }
            .navigationTitle("Opptak")
            .toolbarBackground(Farge.flate, for: .navigationBar)
        }
        .task { await last() }
    }

    private func radInnhold(_ rad: Rad) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Farge.aksent).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(rad.klipp.start, format: .dateTime.hour().minute().second())
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Farge.tekst)
                Text(rad.kamera).font(.caption).foregroundStyle(Farge.dempet)
            }
            // Film-stripa er 4 rammer i én JPEG (~1456x200). Den skal vises HEL —
            // beskjærer man den til 16:9 ser man bare en flis av hendelsen.
            if let u = api.stripeURL(kamera: rad.kamera, alarmUnix: (rad.alarm ?? rad.klipp).sUnix) {
                AsyncImage(url: u) { bilde in
                    bilde.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(Farge.kort2)
                }
                .frame(height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Spacer(minLength: 4)
            Text(varighet(rad.klipp)).font(.caption.monospacedDigit()).foregroundStyle(Farge.svak)
        }
        .padding(.vertical, 4)
    }

    private func klippSkjerm(_ rad: Rad) -> some View {
        ZStack {
            Farge.flate.ignoresSafeArea()
            VStack {
                if let u = api.opptakURL(kamera: rad.kamera, klipp: rad.klipp) {
                    Spiller(url: u, markering: markering(rad), lengde: rad.klipp.lengde)
                        .padding(12)
                } else {
                    Text("Kunne ikke bygge URL").foregroundStyle(Farge.avvik)
                }
                Spacer()
            }
        }
        .navigationTitle(rad.kamera)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Alarmvinduet omregnet til sekunder fra klippets start.
    private func markering(_ rad: Rad) -> (fra: Double, til: Double)? {
        guard let a = rad.alarm else { return nil }
        let fra = max(0, a.sUnix - rad.klipp.sUnix)
        return (fra, max(fra + 1, a.eUnix - rad.klipp.sUnix))
    }

    private func varighet(_ iv: Intervall) -> String {
        let d = Int(iv.lengde.rounded())
        return d < 60 ? "\(d)s" : "\(d / 60)m \(d % 60)s"
    }

    private func last() async {
        laster = true
        defer { laster = false }
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { feil = error.localizedDescription }
    }
}
