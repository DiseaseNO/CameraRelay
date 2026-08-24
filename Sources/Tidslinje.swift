import SwiftUI

/// Tidslinje med ett spor per kamera. Samme prinsipper som vegg-dashbordet, tilpasset
/// en smal skjerm:
///
///  - Bolkene har EKSAKT bredde etter klippets lengde (min. 2 px, ellers forsvinner korte)
///  - Skinna langs bunnen markerer strekket med kontinuerlig opptak — ubrutt der det finnes,
///    og helt borte lenger tilbake der bare klippene er igjen
///  - Motion-alarmen tegnes ikke separat: den ligger alltid inni sitt klipp, og to farger
///    for samme hendelse ble bare rot
///  - Knip = zoom, dra = panorer. Det synlige vinduet ER utvalget for lista under.
struct Tidslinje: View {
    let kameraer: [KameraTL]
    @Binding var vindu: Vindu
    var påTrykk: (String, Intervall) -> Void

    struct Vindu: Equatable {
        var slutt: Date
        var spenn: TimeInterval
        var fra: Date { slutt.addingTimeInterval(-spenn) }
    }

    @State private var spennVedStart: TimeInterval = 0
    @State private var ankerVedStart: Date = .now
    @State private var dro = false

    private let minSpenn: TimeInterval = 120
    private let maksSpenn: TimeInterval = 7 * 24 * 3600

    var body: some View {
        VStack(spacing: 8) {
            topplinje
            GeometryReader { geo in
                VStack(spacing: 6) {
                    ForEach(kameraer, id: \.navn) { kam in
                        spor(kam, bredde: geo.size.width)
                    }
                    akse(bredde: geo.size.width)
                }
                .contentShape(Rectangle())
                .gesture(gester(bredde: geo.size.width))
            }
            .frame(height: CGFloat(kameraer.count) * 40 + 18)
            tegnforklaring
        }
    }

    // MARK: deler

    private var topplinje: some View {
        HStack(spacing: 6) {
            Text(vindu.fra, format: .dateTime.day().month(.abbreviated))
                .font(.caption).foregroundStyle(Farge.dempet)
            Text("\(kort(vindu.fra))–\(kort(vindu.slutt))")
                .font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet)
            Spacer()
            ForEach([1.0, 3.0, 12.0, 24.0], id: \.self) { t in
                let valgt = abs(vindu.spenn - t * 3600) < 60
                Button(t < 24 ? "\(Int(t)) t" : "1 d") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        vindu = .init(slutt: .now, spenn: t * 3600)
                    }
                }
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(valgt ? Farge.aksent.opacity(0.2) : Farge.kort2)
                .foregroundStyle(valgt ? Farge.aksent : Farge.dempet)
                .clipShape(Capsule())
            }
        }
    }

    private func spor(_ kam: KameraTL, bredde: CGFloat) -> some View {
        let klipp = kam.deteksjonsklipp
        let dekning = dekningsstrekk(kam)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(kam.navn).font(.caption2).foregroundStyle(Farge.dempet)
                Spacer()
                Text("\(klipp.filter { synlig($0) }.count)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Farge.svak)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Farge.kort2.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Farge.strek, lineWidth: 1))

                ForEach(Array(dekning.enumerated()), id: \.offset) { _, d in
                    Rectangle().fill(Farge.ok).opacity(0.45)
                        .frame(width: max(1, bredde * andel(d.1 - d.0)), height: 3)
                        .offset(x: bredde * andel(d.0.timeIntervalSince(vindu.fra)), y: 11)
                }
                ForEach(klipp.filter { synlig($0) }, id: \.sUnix) { iv in
                    RoundedRectangle(cornerRadius: 2).fill(Farge.aksent)
                        .frame(width: max(2, bredde * andel(iv.lengde)), height: 18)
                        .offset(x: bredde * andel(iv.start.timeIntervalSince(vindu.fra)), y: -1)
                        .onTapGesture { if !dro { påTrykk(kam.navn, iv) } }
                }
            }
            .frame(height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func akse(bredde: CGFloat) -> some View {
        let steg = aksesteg()
        let start = ceil(vindu.fra.timeIntervalSince1970 / steg) * steg
        let merker = stride(from: start, through: vindu.slutt.timeIntervalSince1970, by: steg)
            .map { Date(timeIntervalSince1970: $0) }
        return ZStack(alignment: .leading) {
            ForEach(merker, id: \.self) { t in
                Text(kort(t))
                    .font(.system(size: 9).monospacedDigit()).foregroundStyle(Farge.svak)
                    .offset(x: bredde * andel(t.timeIntervalSince(vindu.fra)) - 16)
            }
        }
        .frame(height: 12, alignment: .leading)
    }

    private var tegnforklaring: some View {
        HStack(spacing: 10) {
            merke(Farge.aksent, "klipp", høyde: 8)
            merke(Farge.ok.opacity(0.5), "konstant opptak", høyde: 3)
            Spacer()
            Text("knip = zoom").font(.system(size: 9)).foregroundStyle(Farge.svak)
        }
    }

    private func merke(_ farge: Color, _ tekst: String, høyde: CGFloat) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(farge).frame(width: 8, height: høyde)
            Text(tekst).font(.system(size: 9)).foregroundStyle(Farge.svak)
        }
    }

    // MARK: gester

    private func gester(bredde: CGFloat) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    if spennVedStart == 0 {
                        spennVedStart = vindu.spenn
                        ankerVedStart = vindu.slutt
                    }
                    dro = true
                    let nytt = min(max(spennVedStart / g.magnification, minSpenn), maksSpenn)
                    vindu = .init(slutt: ankerVedStart, spenn: nytt)
                }
                .onEnded { _ in spennVedStart = 0; etterGest() },
            DragGesture()
                .onChanged { g in
                    if spennVedStart == 0 {
                        spennVedStart = vindu.spenn
                        ankerVedStart = vindu.slutt
                    }
                    if abs(g.translation.width) > 3 { dro = true }
                    // Dra mot høyre = bakover i tid.
                    let forskyv = Double(-g.translation.width / max(bredde, 1)) * spennVedStart
                    vindu = .init(slutt: min(ankerVedStart.addingTimeInterval(forskyv),
                                             Date.now.addingTimeInterval(300)),
                                  spenn: spennVedStart)
                }
                .onEnded { _ in spennVedStart = 0; etterGest() }
        )
    }

    /// Klikk skal ikke utløses av en drag. Nullstilles like etter at gesten slipper.
    private func etterGest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { dro = false }
    }

    // MARK: regning

    private func andel(_ t: TimeInterval) -> CGFloat { CGFloat(t / vindu.spenn) }

    private func synlig(_ iv: Intervall) -> Bool {
        iv.slutt >= vindu.fra && iv.start <= vindu.slutt
    }

    /// Sammenhengende strekk med video, men BARE der det finnes kontinuerlig opptak.
    /// Ellers ville skinna gjentatt det de gule bolkene allerede sier.
    private func dekningsstrekk(_ kam: KameraTL) -> [(Date, Date)] {
        let kont = kam.kontinuerlig
        guard let første = kont.map(\.sUnix).min(), let siste = kont.map(\.eUnix).max() else { return [] }
        let alle = (kont + kam.deteksjonsklipp).sorted { $0.sUnix < $1.sUnix }
        var ut: [(Double, Double)] = []
        for iv in alle {
            if let sist = ut.last, iv.sUnix <= sist.1 + 2 {
                ut[ut.count - 1].1 = max(sist.1, iv.eUnix)
            } else {
                ut.append((iv.sUnix, iv.eUnix))
            }
        }
        return ut.compactMap { par in
            let a = max(par.0, første), b = min(par.1, siste)
            guard b - a >= 2 else { return nil }
            return (Date(timeIntervalSince1970: a), Date(timeIntervalSince1970: b))
        }
    }

    private func aksesteg() -> TimeInterval {
        let kandidater: [TimeInterval] = [60, 300, 900, 1800, 3600, 7200, 21600, 43200, 86400]
        return kandidater.first { vindu.spenn / $0 <= 6 } ?? 86400 * 7
    }

    private func kort(_ d: Date) -> String {
        d.formatted(.dateTime.hour().minute())
    }
}
