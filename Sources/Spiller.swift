import SwiftUI
import AVKit

/// AVPlayer-lag med digital pinch-zoom, som i web-spilleren. Bildet er 4K, så det er
/// ekte detalj å hente ut — vi forstørrer det vi allerede har, uten å be recorderen om noe.
struct Spiller: View {
    let url: URL
    /// Selve bevegelsen, i sekunder fra klippets start. Vises som gult felt i baren.
    var markering: (fra: Double, til: Double)?
    var lengde: Double?

    @State private var spiller = AVPlayer()
    @State private var tid: Double = 0
    @State private var varighet: Double = 0
    @State private var går = true
    @State private var zoom: CGFloat = 1
    @State private var skyv: CGSize = .zero
    @State private var zoomVedStart: CGFloat = 1
    @State private var skyvVedStart: CGSize = .zero
    @State private var observatør: Any?

    private let maksZoom: CGFloat = 6

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                VideoPlayer(player: spiller)
                    .scaleEffect(zoom)
                    .offset(skyv)
                    .clipped()
                    .gesture(
                        SimultaneousGesture(
                            MagnifyGesture()
                                .onChanged { g in
                                    zoom = min(max(1, zoomVedStart * g.magnification), maksZoom)
                                    skyv = klem(skyv, zoom, geo.size)
                                }
                                .onEnded { _ in zoomVedStart = zoom },
                            DragGesture()
                                .onChanged { g in
                                    guard zoom > 1 else { return }
                                    skyv = klem(CGSize(width: skyvVedStart.width + g.translation.width,
                                                       height: skyvVedStart.height + g.translation.height),
                                                zoom, geo.size)
                                }
                                .onEnded { _ in skyvVedStart = skyv }
                        )
                    )
                    .overlay(alignment: .topTrailing) {
                        if zoom > 1.02 {
                            Button("\(zoom, specifier: "%.1f")× · nullstill") { nullstill() }
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.black.opacity(0.6)).foregroundStyle(Farge.tekst)
                                .clipShape(Capsule()).padding(8)
                        }
                    }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            bar
        }
        .onAppear { start() }
        .onDisappear { stopp() }
    }

    // Egen kontrollbar, ikke AVPlayers egen: den gule markeringen for selve bevegelsen
    // ligger UNDER framdriften, så den aldri dekkes.
    private var bar: some View {
        HStack(spacing: 12) {
            Button { går ? spiller.pause() : spiller.play(); går.toggle() } label: {
                Image(systemName: går ? "pause.fill" : "play.fill")
                    .frame(width: 40, height: 40).background(Farge.kort2)
                    .foregroundStyle(Farge.tekst)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text(mmss(tid)).font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet).frame(width: 42)

            GeometryReader { geo in
                VStack(spacing: 4) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Farge.strek).frame(height: 6)
                        Capsule().fill(Farge.tekst).frame(width: geo.size.width * andel(tid), height: 6)
                    }
                    ZStack(alignment: .leading) {
                        Color.clear.frame(height: 5)
                        if let m = markering, total > 0 {
                            Capsule().fill(Farge.aksent)
                                .frame(width: max(3, geo.size.width * (andel(m.til) - andel(m.fra))), height: 5)
                                .offset(x: geo.size.width * andel(m.fra))
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    guard total > 0 else { return }
                    let t = max(0, min(total, Double(g.location.x / geo.size.width) * total))
                    tid = t
                    spiller.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero)
                })
            }
            .frame(height: 20)

            Text(mmss(total)).font(.caption.monospacedDigit()).foregroundStyle(Farge.dempet).frame(width: 42)
        }
    }

    private var total: Double { lengde ?? varighet }
    private func andel(_ t: Double) -> Double { total > 0 ? max(0, min(1, t / total)) : 0 }
    private func mmss(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
    /// Kanten skal aldri komme innenfor rammen når man drar et zoomet bilde.
    private func klem(_ s: CGSize, _ z: CGFloat, _ ramme: CGSize) -> CGSize {
        let maksX = (z - 1) * ramme.width / 2, maksY = (z - 1) * ramme.height / 2
        return CGSize(width: min(max(s.width, -maksX), maksX),
                      height: min(max(s.height, -maksY), maksY))
    }
    private func nullstill() { zoom = 1; zoomVedStart = 1; skyv = .zero; skyvVedStart = .zero }

    private func start() {
        spiller.replaceCurrentItem(with: AVPlayerItem(url: url))
        spiller.play()
        observatør = spiller.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { t in
            tid = t.seconds
            if let d = spiller.currentItem?.duration.seconds, d.isFinite, d > 0 { varighet = d }
        }
    }
    private func stopp() {
        if let o = observatør { spiller.removeTimeObserver(o) }
        observatør = nil
        spiller.pause()
        spiller.replaceCurrentItem(with: nil)
    }
}
