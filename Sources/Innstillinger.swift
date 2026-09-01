import SwiftUI
import UIKit

/// Innstillinger — en ren meny, ikke en vegg.
///
/// Alt lå på én side før: server, statistikk, feilsøking, om-informasjon og en
/// destruktiv knapp, rett under hverandre. Det ble mye å lese seg gjennom for å finne
/// én ting. Nå er hver del sin egen underside, og forsiden er bare veivalgene.
///
/// `List` framfor `ScrollView` med egne kort: den klipper innholdet til bredden, så
/// ingenting kan skyve siden sidelengs — det var det som gjorde at hele skjermen lot seg
/// dra til høyre og venstre.
struct Innstillinger: View {
    let api: API
    @State private var bekreft = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Rad("Server", api.vert ?? "—")
                    NavigationLink { DriftSide(api: api) } label: {
                        merke("Drift", "waveform.path.ecg", "tjenester og opptaksenhetens ressurser")
                    }
                    NavigationLink { FeilsøkingSide(api: api) } label: {
                        merke("Feilsøking", "stethoscope", "test forbindelsen ledd for ledd")
                    }
                } header: { overskrift("Server") }

                Section {
                    NavigationLink { StatistikkSide(api: api) } label: {
                        merke("Statistikk", "chart.bar", "kameraer, hendelser og bildebruk")
                    }
                } header: { overskrift("Kameraer") }

                Section {
                    NavigationLink { OmSide() } label: {
                        merke("Om appen", "info.circle", versjon)
                    }
                } header: { overskrift("Om") }

                Section {
                    Button(role: .destructive) { bekreft = true } label: {
                        Text("Glem denne enheten").foregroundStyle(Farge.avvik)
                    }
                } footer: {
                    Text("Enhets-tokenet ligger i Keychain og kan trekkes tilbake fra "
                         + "dashbordet under Admin → Enheter.")
                        .font(.caption).foregroundStyle(Farge.svak)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Farge.flate)
            .navigationTitle("Innstillinger")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .confirmationDialog("Glemme enheten?", isPresented: $bekreft, titleVisibility: .visible) {
                Button("Glem", role: .destructive) { api.glemEnhet() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Du må pare på nytt med en ny kode fra dashbordet.")
            }
        }
    }

    private var versjon: String {
        let i = Bundle.main.infoDictionary
        return "versjon \(i?["CFBundleShortVersionString"] as? String ?? "?") "
            + "(\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    private func merke(_ tittel: String, _ ikon: String, _ under: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ikon).font(.footnote).foregroundStyle(Farge.aksent).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(tittel).font(.subheadline).foregroundStyle(Farge.tekst)
                Text(under).font(.caption2).foregroundStyle(Farge.svak).lineLimit(1)
            }
        }
    }

    private func overskrift(_ s: String) -> some View {
        Text(s).font(.caption).foregroundStyle(Farge.dempet)
    }
}

/// Felles ramme for undersidene: samme bakgrunn, skjult rullefelt, egen tittel.
private struct Side<Innhold: View>: View {
    let tittel: String
    @ViewBuilder var innhold: () -> Innhold

    var body: some View {
        ZStack {
            Farge.flate.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { innhold() }
                    .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(tittel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Farge.flate, for: .navigationBar)
    }
}

// MARK: - undersider

private struct DriftSide: View {
    let api: API
    var body: some View {
        Side(tittel: "Drift") { Drift(api: api) }
    }
}

private struct StatistikkSide: View {
    let api: API
    @State private var kameraer: [KameraTL] = []

    var body: some View {
        Side(tittel: "Statistikk") {
            Boks("Kameraer") {
                Rad("Kameraer", "\(kameraer.count)")
                Rad("Hendelser totalt", "\(kameraer.reduce(0) { $0 + $1.deteksjonsklipp.count })")
                ForEach(kameraer, id: \.navn) { kam in
                    Rad(kam.navn, "\(kam.deteksjonsklipp.count) klipp")
                }
            }
            Boks("Bilder") {
                Rad("Hentet", "\(Bildelager.delt.antallHentet)")
                Rad("Data", String(format: "%.1f MB", Double(Bildelager.delt.bytesHentet) / 1_048_576))
                Rad("Feilet", "\(Bildelager.delt.antallFeilet)")
                Button("Tøm bildelager") { Bildelager.delt.tøm() }
                    .font(.caption).foregroundStyle(Farge.aksent).padding(.top, 2)
            }
        }
        .task { kameraer = (try? await api.tidslinje()) ?? [] }
    }
}

/// Går gjennom leddene i rekkefølge, så man ser HVOR det stopper — ikke bare at «noe»
/// er galt. Det er stor forskjell på «serveren svarer ikke» og «serveren svarer, men
/// kameraet er nede».
private struct FeilsøkingSide: View {
    let api: API
    @State private var sjekker = false
    @State private var resultat: [Sjekk] = []

    struct Sjekk: Identifiable {
        let id = UUID()
        let navn: String, ok: Bool, detalj: String
    }

    var body: some View {
        Side(tittel: "Feilsøking") {
            Boks("Resultat") {
                if resultat.isEmpty && !sjekker {
                    Text("Ikke kjørt ennå.").font(.caption).foregroundStyle(Farge.svak)
                }
                ForEach(resultat) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.ok ? Farge.ok : Farge.avvik)
                            .font(.caption)
                        Text(r.navn).font(.caption).foregroundStyle(Farge.tekst).layoutPriority(1)
                        Spacer(minLength: 0)
                        Text(r.detalj)
                            .font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet)
                            .lineLimit(2).multilineTextAlignment(.trailing)
                    }
                }
                Button { Task { await kjør() } } label: {
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
    }

    private func kjør() async {
        sjekker = true
        resultat = []
        defer { sjekker = false }
        let start = Date()
        do {
            let kam = try await api.tidslinje()
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            resultat.append(.init(navn: "Backend svarer", ok: true, detalj: "\(ms) ms"))
            resultat.append(.init(navn: "Token godtatt", ok: true, detalj: "ok"))
            resultat.append(.init(navn: "Kameraer funnet", ok: !kam.isEmpty, detalj: "\(kam.count)"))
            for k in kam {
                let fersk = k.deteksjonsklipp.last.map { Int(Date().timeIntervalSince($0.slutt) / 60) }
                resultat.append(.init(navn: k.navn, ok: (fersk ?? 999) < 120,
                                      detalj: fersk.map { "siste for \($0) min siden" } ?? "ingen klipp"))
            }
        } catch {
            resultat.append(.init(navn: "Backend svarer", ok: false, detalj: error.localizedDescription))
        }
    }
}

private struct OmSide: View {
    var body: some View {
        Side(tittel: "Om appen") {
            Boks("Appen") {
                let info = Bundle.main.infoDictionary
                Rad("Versjon", info?["CFBundleShortVersionString"] as? String ?? "?")
                Rad("Bygg", info?["CFBundleVersion"] as? String ?? "?")
            }
            Boks("Enhet") {
                Rad("Navn", UIDevice.current.name)
                Rad("iOS", UIDevice.current.systemVersion)
            }
        }
    }
}
