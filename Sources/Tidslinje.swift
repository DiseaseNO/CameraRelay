import SwiftUI

/// Tidslinje for ETT kamera, med spillehode — inspirert av hvordan Tapo løser det.
///
/// Forskjellen fra en ren velger er at linja viser HVOR DU ER, ikke bare hva som finnes.
/// Det gjør den til et navigasjonsverktøy: dra spillehodet, og klippet under følger med.
///
///  - Hendelser er tynne streker, ikke blokker. På dagsnivå ER et 40-sekunders klipp en strek,
///    og å tegne det bredere ville løyet om lengden.
///  - Skinna langs bunnen markerer strekket med kontinuerlig opptak, og forsvinner der bare
///    klippene er igjen — ellers gjentar den bare det strekene sier.
///  - Knip zoomer, dra flytter spillehodet. Tidsboblen viser eksakt tidspunkt underveis.
struct Tidslinje: View {
    let kamera: KameraTL?
    @Binding var vindu: Vindu
    /// Tidspunktet spillehodet står på. Settes av dra, og av at et klipp velges.
    @Binding var hode: Date
    var påValg: (Intervall) -> Void

    struct Vindu: Equatable {
        var midt: Date
        var spenn: TimeInterval
        var fra: Date { midt.addingTimeInterval(-spenn / 2) }
        var til: Date { midt.addingTimeInterval(spenn / 2) }
    }

    @State private var spennVedStart: TimeInterval = 0
    @State private var drar = false

    // Ned til 1 minutt: da er et 40-sekunders klipp to tredjedeler av linja, og lengden
    // er umulig å misforstå. Zoom er det eneste som virkelig løser lengde på tidsakse.
    private let minSpenn: TimeInterval = 60
    // Maks 2 timer. Regnestykket: for at et 40-sekunders klipp skal bli minst 2 pt bredt
    // på en ~360 pt linje, må vinduet være ≤ 7200 s. Zoomer man lenger ut, treffer alle
    // streker minstebredden og linja LYVER om lengden. Da er det bedre å ikke tillate det —
    // dagsnavigasjon gjøres med datopilene og lista, ikke ved å zoome ut i det uendelige.
    private let maksSpenn: TimeInterval = 2 * 3600

    var body: some View {
        VStack(spacing: 4) {
            akse
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Farge.kort2)

                    // Dekning som TYNN SKINNE langs bunnen. Som fylt flate overdøvet den
                    // hendelsene fullstendig — og de er det man er ute etter.
                    ForEach(Array(dekning.enumerated()), id: \.offset) { _, d in
                        Rectangle().fill(Farge.ok).opacity(0.55)
                            .frame(width: max(1, bredde(d.1.timeIntervalSince(d.0), geo)), height: 4)
                            .offset(x: x(d.0, geo), y: 29)
                    }

                    // Hendelser i EKSAKT bredde. Gulvet er 1,5 pt — akkurat nok til at et
                    // klipp ikke forsvinner helt, men lavt nok til at forskjellen mellom
                    // 40 s og 70 s faktisk vises. Et høyere gulv (jeg hadde 2 pt) gjør alle
                    // streker like brede og løy om lengden.
                    ForEach(synligeKlipp, id: \.sUnix) { iv in
                        Rectangle().fill(Farge.aksent)
                            .frame(width: max(1.5, bredde(iv.lengde, geo)), height: 52)
                            .offset(x: x(iv.start, geo), y: -3)
                    }

                    // spillehode
                    Rectangle().fill(.white).frame(width: 2)
                        .offset(x: x(hode, geo) - 1)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
                .frame(height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .gesture(gester(geo))
                .overlay(alignment: .top) { boble(geo) }
            }
            .frame(height: 62)
        }
    }

    // MARK: deler

    private var akse: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ForEach(merker, id: \.self) { t in
                    VStack(spacing: 1) {
                        Rectangle().fill(Farge.strek).frame(width: 1, height: 4)
                        Text(t, format: .dateTime.hour().minute())
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(Farge.svak)
                    }
                    .offset(x: x(t, geo) - 16)
                }
            }
        }
        .frame(height: 18)
    }

    /// Tidsboble over spillehodet — den gjør dragingen presis i stedet for omtrentlig.
    private func boble(_ geo: GeometryProxy) -> some View {
        Text(hode, format: .dateTime.hour().minute().second())
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(drar ? Farge.aksent : Farge.kort2)
            .foregroundStyle(drar ? Farge.flate : Farge.tekst)
            .clipShape(Capsule())
            .offset(x: min(max(x(hode, geo) - 34, 0), max(geo.size.width - 68, 0)), y: -22)
            .animation(.easeOut(duration: 0.12), value: drar)
    }

    // MARK: gester

    private func gester(_ geo: GeometryProxy) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    if spennVedStart == 0 { spennVedStart = vindu.spenn }
                    vindu.spenn = min(max(spennVedStart / g.magnification, minSpenn), maksSpenn)
                }
                .onEnded { _ in spennVedStart = 0 },
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    drar = true
                    // Drar man UT av kanten, panorerer vinduet i stedet for at spillehodet
                    // stopper. Nødvendig nå som man ikke kan zoome ut til hele døgnet.
                    let b = geo.size.width
                    if g.location.x < 0 || g.location.x > b {
                        let over = g.location.x < 0 ? g.location.x : g.location.x - b
                        let skritt = Double(over / max(b, 1)) * vindu.spenn * 0.35
                        vindu.midt = min(vindu.midt.addingTimeInterval(skritt),
                                         Date.now.addingTimeInterval(vindu.spenn / 2))
                    }
                    hode = tid(g.location.x, geo)
                }
                .onEnded { _ in
                    drar = false
                    // Slipp = velg klippet spillehodet står på (eller nærmeste innen 5 min).
                    if let iv = nærmesteKlipp(hode) { påValg(iv) }
                }
        )
    }

    // MARK: regning

    private var synligeKlipp: [Intervall] {
        (kamera?.deteksjonsklipp ?? []).filter { $0.slutt >= vindu.fra && $0.start <= vindu.til }
    }

    private var dekning: [(Date, Date)] {
        guard let kam = kamera else { return [] }
        let kont = kam.kontinuerlig
        guard let a = kont.map(\.sUnix).min(), let b = kont.map(\.eUnix).max() else { return [] }
        var ut: [(Double, Double)] = []
        for iv in (kont + kam.deteksjonsklipp).sorted(by: { $0.sUnix < $1.sUnix }) {
            if let sist = ut.last, iv.sUnix <= sist.1 + 2 { ut[ut.count - 1].1 = max(sist.1, iv.eUnix) }
            else { ut.append((iv.sUnix, iv.eUnix)) }
        }
        return ut.compactMap {
            let s = max($0.0, a), e = min($0.1, b)
            guard e - s >= 2 else { return nil }
            return (Date(timeIntervalSince1970: s), Date(timeIntervalSince1970: e))
        }
    }

    private func nærmesteKlipp(_ t: Date) -> Intervall? {
        (kamera?.deteksjonsklipp ?? [])
            .min { a, b in avstand(a, t) < avstand(b, t) }
            .flatMap { avstand($0, t) <= 300 ? $0 : nil }
    }

    private func avstand(_ iv: Intervall, _ t: Date) -> TimeInterval {
        let u = t.timeIntervalSince1970
        if u < iv.sUnix { return iv.sUnix - u }
        if u > iv.eUnix { return u - iv.eUnix }
        return 0
    }

    private func x(_ t: Date, _ geo: GeometryProxy) -> CGFloat {
        CGFloat(t.timeIntervalSince(vindu.fra) / vindu.spenn) * geo.size.width
    }
    private func bredde(_ t: TimeInterval, _ geo: GeometryProxy) -> CGFloat {
        CGFloat(t / vindu.spenn) * geo.size.width
    }
    private func tid(_ x: CGFloat, _ geo: GeometryProxy) -> Date {
        let andel = min(max(Double(x / max(geo.size.width, 1)), 0), 1)
        return vindu.fra.addingTimeInterval(andel * vindu.spenn)
    }

    private var merker: [Date] {
        let steg: TimeInterval = [300, 900, 1800, 3600, 7200, 21600]
            .first { vindu.spenn / $0 <= 5 } ?? 43200
        let start = ceil(vindu.fra.timeIntervalSince1970 / steg) * steg
        return stride(from: start, through: vindu.til.timeIntervalSince1970, by: steg)
            .map { Date(timeIntervalSince1970: $0) }
    }
}
