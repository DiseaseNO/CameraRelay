import SwiftUI

/// Avspilling med rask veksling mellom klipp.
///
/// Det som gjør dette til en mobilskjerm og ikke bare en spiller: du skal aldri måtte gå
/// tilbake til lista for å se neste hendelse. Tre veier videre, i økende presisjon:
///
///   - **Sveip** til venstre/høyre på bildet — raskest, uten å se ned
///   - **Piltastene** ved siden av tidsstempelet — presist, med tommelen
///   - **Stripe-karusellen** under — du SER hva du hopper til før du trykker
///
/// Karusellen bruker recorderens ferdige film-striper, så den koster ingenting ekstra:
/// bildene er allerede hentet for lista.
struct SpillerSkjerm: View {
    let api: API
    let klipp: [Klipp]
    let start: Int

    @Environment(\.dismiss) private var lukk
    @State private var indeks: Int = 0
    @State private var sveip: CGFloat = 0

    private var nå: Klipp? { klipp.indices.contains(indeks) ? klipp[indeks] : nil }

    var body: some View {
        ZStack {
            Farge.flate.ignoresSafeArea()
            VStack(spacing: 12) {
                topplinje
                if let k = nå, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
                    Spiller(url: url, markering: k.markering, lengde: k.iv.lengde)
                        .id(k.id)          // ny spiller per klipp — ellers henger forrige igjen
                        .offset(x: sveip)
                        .gesture(sveipeGest)
                } else {
                    Spacer()
                    Text("Fant ikke klippet.").foregroundStyle(Farge.avvik)
                    Spacer()
                }
                karusell
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .onAppear { indeks = start }
    }

    // MARK: deler

    private var topplinje: some View {
        HStack(spacing: 12) {
            Button { lukk() } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 36, height: 36)
                    .background(Farge.kort2).foregroundStyle(Farge.tekst)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(nå?.kamera ?? "—").font(.subheadline.weight(.medium)).foregroundStyle(Farge.tekst)
                if let k = nå {
                    Text(k.iv.start, format: .dateTime.day().month(.abbreviated).hour().minute().second())
                        .font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet)
                }
            }
            Spacer()
            bla(retning: -1, ikon: "chevron.left")
            Text("\(indeks + 1)/\(klipp.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(Farge.svak)
            bla(retning: 1, ikon: "chevron.right")
        }
    }

    private func bla(retning: Int, ikon: String) -> some View {
        let mål = indeks + retning
        return Button { gåTil(mål) } label: {
            Image(systemName: ikon)
                .frame(width: 34, height: 34)
                .background(Farge.kort2)
                .foregroundStyle(klipp.indices.contains(mål) ? Farge.tekst : Farge.svak)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .disabled(!klipp.indices.contains(mål))
    }

    private var karusell: some View {
        ScrollViewReader { rull in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(klipp.enumerated()), id: \.element.id) { i, k in
                        Button { gåTil(i) } label: {
                            VStack(spacing: 3) {
                                Stripe(api: api, klipp: k)
                                    .frame(width: 104, height: 30)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(i == indeks ? Farge.aksent : Farge.strek,
                                                    lineWidth: i == indeks ? 2 : 1)
                                    )
                                Text(k.iv.start, format: .dateTime.hour().minute())
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(i == indeks ? Farge.aksent : Farge.svak)
                            }
                        }
                        .id(i)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: 48)
            .onChange(of: indeks) { _, ny in
                withAnimation(.easeOut(duration: 0.25)) { rull.scrollTo(ny, anchor: .center) }
            }
        }
    }

    // MARK: navigasjon

    /// Sveip på bildet. Terskelen er romslig (60 pt) fordi pinch-zoom i selve videoen
    /// bruker samme flate — små bevegelser skal ikke bytte klipp ved et uhell.
    private var sveipeGest: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { g in sveip = g.translation.width / 3 }
            .onEnded { g in
                let retning = g.translation.width < -60 ? 1 : (g.translation.width > 60 ? -1 : 0)
                withAnimation(.easeOut(duration: 0.2)) { sveip = 0 }
                if retning != 0 { gåTil(indeks + retning) }
            }
    }

    private func gåTil(_ i: Int) {
        guard klipp.indices.contains(i), i != indeks else { return }
        indeks = i
    }
}
