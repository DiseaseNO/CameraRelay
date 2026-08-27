import SwiftUI

/// Handlingene som hører til ETT klipp: last ned til kamerarullen, og lås mot sletting.
///
/// Samme knapperad brukes på Opptak-fanen og på Låste-fanen — et låst klipp skal se og
/// oppføre seg likt uansett hvor man finner det.
///
/// Låsestatusen kommer INN som en verdi. Vi spør bevisst ikke recorderen per klipp: å slå
/// opp ett opptak får den til å generere klippet, og hadde vi gjort det for hver rad man
/// blar forbi, ville lista alene lagt recorderen ned. Statusen hentes i stedet med ett
/// kall (`/api/kamera/laste`) og sammenlignes lokalt.
struct Klippknapper: View {
    let api: API
    let kamera: String
    let klipp: Intervall
    var sub: Int = 2
    let låst: Bool
    /// Kalles når låsen faktisk er endret hos recorderen, med den nye tilstanden.
    let påLåsEndret: (Bool) -> Void

    @State private var nedlaster = Nedlaster()
    @State private var låser = false
    @State private var låsefeil: String?
    @State private var bekreftOpplås = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                knapp(tittel: nedlaster.laster ? "Laster ned…" : "Last ned",
                      ikon: "arrow.down.to.line",
                      aktiv: false,
                      opptatt: nedlaster.laster) {
                    Task { await nedlaster.lastNed(api: api, kamera: kamera, klipp: klipp, sub: sub) }
                }
                knapp(tittel: låst ? "Låst" : "Lås",
                      ikon: låst ? "lock.fill" : "lock.open",
                      aktiv: låst,
                      opptatt: låser) {
                    // Å låse er ufarlig. Å låse OPP er den ene handlingen her som kan
                    // ende med at opptaket forsvinner ved neste opprydding, så den skal
                    // ikke kunne skje med et uhell-trykk.
                    if låst { bekreftOpplås = true } else { Task { await settLås(true) } }
                }
            }
            if let m = låsefeil ?? nedlaster.melding {
                Text(m)
                    .font(.caption2)
                    .foregroundStyle(erFeil(m) ? Farge.avvik : Farge.ok)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .confirmationDialog("Lås opp klippet?", isPresented: $bekreftOpplås, titleVisibility: .visible) {
            Button("Lås opp", role: .destructive) { Task { await settLås(false) } }
            Button("Avbryt", role: .cancel) { }
        } message: {
            Text("Da kan opptaket bli slettet når disken går full.")
        }
        .animation(.easeOut(duration: 0.2), value: nedlaster.tilstand)
        .onChange(of: klipp.sUnix) { _, _ in nedlaster.nullstill(); låsefeil = nil }
        // «Lagret i kamerarullen» skal si fra og så forsvinne — ikke bli stående som
        // et varsel man må gjøre noe med.
        .onChange(of: nedlaster.tilstand) { _, ny in
            guard ny == .ferdig else { return }
            Task {
                try? await Task.sleep(for: .seconds(4))
                if nedlaster.tilstand == .ferdig { nedlaster.nullstill() }
            }
        }
    }

    private func erFeil(_ m: String) -> Bool { m != "Lagret i kamerarullen" }

    private func settLås(_ lås: Bool) async {
        guard !låser else { return }
        låser = true
        låsefeil = nil
        defer { låser = false }
        do {
            let ny = try await api.settLås(kamera: kamera, klipp: klipp, sub: sub, lås: lås)
            påLåsEndret(ny)
        } catch {
            if !erAvbrutt(error) { låsefeil = error.localizedDescription }
        }
    }

    private func knapp(tittel: String, ikon: String, aktiv: Bool, opptatt: Bool,
                       handling: @escaping () -> Void) -> some View {
        Button(action: handling) {
            HStack(spacing: 6) {
                if opptatt {
                    ProgressView().controlSize(.mini).tint(Farge.dempet)
                } else {
                    Image(systemName: ikon).font(.caption)
                }
                Text(tittel).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(aktiv ? Farge.aksent.opacity(0.2) : Farge.kort2)
            .foregroundStyle(aktiv ? Farge.aksent : Farge.tekst)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(aktiv ? Farge.aksent.opacity(0.45) : Farge.strek, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(opptatt)
    }
}
