import SwiftUI

/// Fanen «Låste»: alle opptak som er beskyttet mot opptaksenhetens opprydding.
///
/// Hvorfor den finnes: opptak slettes IKKE etter en tidsfrist hos oss, de slettes når
/// videodisken går full. Et låst klipp overlever den oppryddingen. Da må man også kunne
/// se hva som faktisk er låst — ellers vet man ikke hva som er trygt før det er borte.
///
/// Lista kommer fra opptaksenheten selv (`evt_filter=12`), ikke fra vårt lokale arkiv. Den
/// viser derfor sannheten også for klipp som er eldre enn de sju døgnene arkivet holder.
struct LåsteVisning: View {
    let api: API

    @State private var klipp: [LåstKlipp] = []
    /// Tidslinja brukes bare til å finne alarm-tidspunktet inne i et klipp, som er
    /// nøkkelen til film-stripa. Er klippet eldre enn arkivet, finner vi den ikke — da
    /// viser vi rada uten bilde framfor å vise feil bilde.
    @State private var kameraer: [KameraTL] = []
    @State private var spilles: LåstKlipp?
    @State private var feil: String?
    @State private var laster = true

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                if laster && klipp.isEmpty {
                    ProgressView().tint(Farge.dempet)
                } else if let feil, klipp.isEmpty {
                    VStack(spacing: 10) {
                        Text(feil).foregroundStyle(Farge.avvik).multilineTextAlignment(.center)
                        Button("Prøv igjen") { Task { await last() } }.foregroundStyle(Farge.aksent)
                    }.padding()
                } else if klipp.isEmpty {
                    tomt
                } else {
                    innhold
                }
            }
            .navigationTitle("Låste")
            .toolbarBackground(Farge.flate, for: .navigationBar)
        }
        .task { await last() }
    }

    private var tomt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open").font(.system(size: 34)).foregroundStyle(Farge.svak)
            Text("Ingen låste opptak").font(.subheadline).foregroundStyle(Farge.dempet)
            Text("Lås et klipp på Opptak-fanen, så blir det liggende her selv når disken går full.")
                .font(.caption).foregroundStyle(Farge.svak)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var innhold: some View {
        VStack(spacing: 0) {
            if let k = spilles, let url = api.opptakURL(kamera: k.navn, klipp: k.intervall, sub: k.sub) {
                Spiller(url: url, markering: nil, lengde: k.lengde)
                    .id(k.id)
                    .padding(.top, 6)
                    .layoutPriority(1)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(klipp) { k in
                        rad(k)
                    }
                }
                .padding(12)
            }
            .refreshable { await last() }
        }
    }

    private func rad(_ k: LåstKlipp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { spilles = k } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Farge.aksent)
                        Text(k.navn).font(.subheadline.weight(.medium)).foregroundStyle(Farge.tekst)
                        Spacer()
                        Text(k.start, format: .dateTime.day().month().hour().minute().second())
                            .font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet)
                    }
                    if let stripe = somKlipp(k) {
                        Stripe(api: api, klipp: stripe)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1456.0 / 200.0, contentMode: .fit)
                    }
                    HStack(spacing: 8) {
                        Text(k.sub == 1 ? "kontinuerlig" : "bevegelse")
                            .font(.caption2).foregroundStyle(Farge.svak)
                        Text(varighet(k.lengde)).font(.caption2.monospacedDigit()).foregroundStyle(Farge.svak)
                        Spacer()
                        if spilles?.id == k.id {
                            Text("spilles").font(.caption2).foregroundStyle(Farge.aksent)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Klippknapper(api: api, kamera: k.navn, klipp: k.intervall, sub: k.sub, låst: true) { nyLåst in
                // Låst opp herfra betyr at klippet ikke lenger hører hjemme i lista.
                if !nyLåst {
                    if spilles?.id == k.id { spilles = nil }
                    klipp.removeAll { $0.id == k.id }
                }
            }
        }
        .padding(10)
        .background(Farge.kort)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(spilles?.id == k.id ? Farge.aksent : Farge.strek, lineWidth: spilles?.id == k.id ? 2 : 1))
    }

    /// Finner alarm-tidspunktet inne i det låste klippet, så film-stripa kan hentes.
    /// Ingen treff = klippet er eldre enn arkivet; da dropper vi bildet.
    private func somKlipp(_ k: LåstKlipp) -> Klipp? {
        guard let kam = kameraer.first(where: { $0.navn == k.navn }),
              let alarm = kam.alarm(i: k.intervall) else { return nil }
        return Klipp(kamera: k.navn, iv: k.intervall, alarm: alarm)
    }

    private func varighet(_ t: TimeInterval) -> String {
        let d = Int(t.rounded())
        return String(format: "%d:%02d", d / 60, d % 60)
    }

    private func last() async {
        laster = klipp.isEmpty
        defer { laster = false }
        do {
            klipp = try await api.låsteKlipp()
            // Tidslinja er bare til film-stripene. Feiler den, er lista fortsatt riktig.
            kameraer = (try? await api.tidslinje()) ?? kameraer
            feil = nil
        } catch {
            if !erAvbrutt(error) { feil = error.localizedDescription }
        }
    }
}
