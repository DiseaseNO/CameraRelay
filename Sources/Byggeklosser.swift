import SwiftUI

/// Kortflate med overskrift over. Brukes på undersidene i Innstillinger.
///
/// `tilbehør` er plassen til høyre i overskriften — i praksis en oppdater-knapp.
struct Boks<Innhold: View, Tilbehør: View>: View {
    private let tittel: String
    private let innhold: () -> Innhold
    private let tilbehør: () -> Tilbehør

    init(_ tittel: String,
         @ViewBuilder innhold: @escaping () -> Innhold,
         @ViewBuilder tilbehør: @escaping () -> Tilbehør) {
        self.tittel = tittel
        self.innhold = innhold
        self.tilbehør = tilbehør
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tittel).font(.footnote.weight(.semibold)).foregroundStyle(Farge.dempet)
                Spacer()
                tilbehør()
            }
            VStack(alignment: .leading, spacing: 8) { innhold() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Farge.kort)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

extension Boks where Tilbehør == EmptyView {
    init(_ tittel: String, @ViewBuilder innhold: @escaping () -> Innhold) {
        self.init(tittel, innhold: innhold, tilbehør: { EmptyView() })
    }
}

/// Etikett til venstre, verdi til høyre.
///
/// Verdien får `lineLimit(1)` og krymper heller enn å vokse. Uten det presset lange
/// verdier — fastvarestrengen, en feilmelding — raden bredere enn skjermen, og HELE
/// siden lot seg dra sidelengs.
struct Rad: View {
    private let venstre: String
    private let høyre: String
    init(_ venstre: String, _ høyre: String) { self.venstre = venstre; self.høyre = høyre }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(venstre)
                .font(.caption).foregroundStyle(Farge.dempet)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 0)
            Text(høyre)
                .font(.caption.monospacedDigit()).foregroundStyle(Farge.tekst)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
        }
    }
}
