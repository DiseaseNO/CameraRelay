import SwiftUI
import UIKit

/// Innstillinger, statistikk og feilsøking.
///
/// Feilsøkingsdelen finnes fordi appen snakker med et hjemmelaget oppsett gjennom flere
/// ledd — brannmur, ADC, Caddy, relay, recorder. Når noe ikke virker, er det stor forskjell
/// på «serveren svarer ikke» og «serveren svarer, men kameraet er nede». Denne siden svarer
/// på hvilket ledd som er problemet, uten at man må lete i logger.
struct Innstillinger: View {
    let api: API
    @State private var bekreft = false
    @State private var sjekker = false
    @State private var resultat: [Sjekk] = []
    @State private var kameraer: [KameraTL] = []

    struct Sjekk: Identifiable {
        let id = UUID()
        let navn: String
        let ok: Bool
        let detalj: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        felt("Server", api.vert ?? "—")
                        statistikk
                        feilsøking
                        omApp
                        glemKnapp
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Innstillinger")
            .toolbarBackground(Farge.flate, for: .navigationBar)
        }
        .task { kameraer = (try? await api.tidslinje()) ?? [] }
    }

    // MARK: deler

    private var statistikk: some View {
        boks("Statistikk") {
            rad("Kameraer", "\(kameraer.count)")
            rad("Hendelser totalt", "\(kameraer.reduce(0) { $0 + $1.deteksjonsklipp.count })")
            ForEach(kameraer, id: \.navn) { kam in
                rad(kam.navn, "\(kam.deteksjonsklipp.count) klipp")
            }
            rad("Bilder hentet", "\(Bildelager.delt.antallHentet)")
            rad("Data til bilder", String(format: "%.1f MB", Double(Bildelager.delt.bytesHentet) / 1_048_576))
        }
    }

    private var feilsøking: some View {
        boks("Feilsøking") {
            ForEach(resultat) { r in
                HStack(spacing: 8) {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r.ok ? Farge.ok : Farge.avvik)
                        .font(.caption)
                    Text(r.navn).font(.caption).foregroundStyle(Farge.tekst)
                    Spacer()
                    Text(r.detalj).font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet)
                }
            }
            Button { Task { await kjørSjekk() } } label: {
                HStack {
                    if sjekker { ProgressView().tint(Farge.flate).scaleEffect(0.7) }
                    Text(sjekker ? "Sjekker …" : "Test forbindelsen")
                }
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Farge.aksent).foregroundStyle(Farge.flate)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .disabled(sjekker)
            .padding(.top, 4)
        }
    }

    private var omApp: some View {
        boks("Om") {
            let info = Bundle.main.infoDictionary
            rad("Versjon", "\(info?["CFBundleShortVersionString"] as? String ?? "?") "
                + "(\(info?["CFBundleVersion"] as? String ?? "?"))")
            rad("Enhet", UIDevice.current.name)
            rad("iOS", UIDevice.current.systemVersion)
            Button("Tøm bildelager") { Bildelager.delt.tøm() }
                .font(.caption).foregroundStyle(Farge.aksent).padding(.top, 2)
        }
    }

    private var glemKnapp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhets-tokenet ligger i Keychain og kan trekkes tilbake fra dashbordet under Admin → Enheter.")
                .font(.caption).foregroundStyle(Farge.svak)
            Button(role: .destructive) { bekreft = true } label: {
                Text("Glem denne enheten")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Farge.kort2).foregroundStyle(Farge.avvik)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .confirmationDialog("Glemme enheten?", isPresented: $bekreft, titleVisibility: .visible) {
            Button("Glem", role: .destructive) { api.glemEnhet() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Du må pare på nytt med en ny kode fra dashbordet.")
        }
    }

    // MARK: byggeklosser

    private func boks<Innhold: View>(_ tittel: String, @ViewBuilder _ innhold: () -> Innhold) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tittel).font(.footnote.weight(.semibold)).foregroundStyle(Farge.dempet)
            VStack(alignment: .leading, spacing: 6) { innhold() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Farge.kort)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rad(_ venstre: String, _ høyre: String) -> some View {
        HStack {
            Text(venstre).font(.caption).foregroundStyle(Farge.dempet)
            Spacer()
            Text(høyre).font(.caption.monospacedDigit()).foregroundStyle(Farge.tekst)
        }
    }

    private func felt(_ tittel: String, _ verdi: String) -> some View {
        boks(tittel) { Text(verdi).font(.subheadline).foregroundStyle(Farge.tekst) }
    }

    /// Går gjennom leddene i rekkefølge, så man ser HVOR det stopper — ikke bare at
    /// «noe» er galt.
    private func kjørSjekk() async {
        sjekker = true
        resultat = []
        defer { sjekker = false }

        let start = Date()
        do {
            let kam = try await api.tidslinje()
            kameraer = kam
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            resultat.append(.init(navn: "Backend svarer", ok: true, detalj: "\(ms) ms"))
            resultat.append(.init(navn: "Token godtatt", ok: true, detalj: "ok"))
            resultat.append(.init(navn: "Kameraer funnet", ok: !kam.isEmpty, detalj: "\(kam.count)"))

            for k in kam {
                let fersk = k.deteksjonsklipp.last.map {
                    Int(Date().timeIntervalSince($0.slutt) / 60)
                }
                resultat.append(.init(
                    navn: k.navn,
                    ok: (fersk ?? 999) < 120,
                    detalj: fersk.map { "siste for \($0) min siden" } ?? "ingen klipp"))
            }
        } catch {
            resultat.append(.init(navn: "Backend svarer", ok: false,
                                  detalj: error.localizedDescription))
        }
    }
}
