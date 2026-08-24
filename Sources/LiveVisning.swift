import SwiftUI
import AVKit

/// Kameraene live. Backend pakker recorderens fMP4-strøm som HLS, så AVPlayer får
/// maskinvare-dekoding, låseskjerm-kontroller og AirPlay gratis.
struct LiveVisning: View {
    let api: API
    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var fullskjerm: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(kameraer, id: \.navn) { kam in
                            if let url = api.liveURL(kamera: kam.navn) {
                                LiveKort(navn: kam.navn, url: url) { fullskjerm = kam.navn }
                            }
                        }
                        if let feil {
                            Text(feil).font(.footnote).foregroundStyle(Farge.avvik).padding()
                        }
                    }
                    .padding(12)
                }
                .refreshable { await last() }
            }
            .navigationTitle("Live")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .fullScreenCover(item: Binding(
                get: { fullskjerm.map(Navn.init) },
                set: { fullskjerm = $0?.rawValue }
            )) { n in
                if let url = api.liveURL(kamera: n.rawValue) {
                    Fullskjerm(navn: n.rawValue, url: url) { fullskjerm = nil }
                }
            }
        }
        .task { await last() }
    }

    private func last() async {
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { feil = error.localizedDescription }
    }

    struct Navn: Identifiable { let rawValue: String; var id: String { rawValue } }
}

/// Ett kamera i lista. Spiller AV SEG SELV med én gang — man åpner ikke en kamera-app
/// for å så måtte trykke play. Knip zoomer i bildet; knappen gir full skjerm på tvers.
struct LiveKort: View {
    let navn: String
    let url: URL
    var påFullskjerm: () -> Void

    @State private var spiller = AVPlayer()
    @State private var zoom: CGFloat = 1
    @State private var skyv: CGSize = .zero
    @State private var zoomVedStart: CGFloat = 1
    @State private var skyvVedStart: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(Farge.ok).frame(width: 7, height: 7)
                Text(navn).foregroundStyle(Farge.tekst).font(.subheadline.weight(.medium))
                Spacer()
                if zoom > 1.02 {
                    Button { nullstill() } label: {
                        Text("\(zoom, specifier: "%.1f")×").font(.caption2).foregroundStyle(Farge.aksent)
                    }
                    .padding(.trailing, 8)
                }
                Button(action: påFullskjerm) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote).foregroundStyle(Farge.dempet)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            GeometryReader { geo in
                VideoPlayer(player: spiller)
                    .scaleEffect(zoom)
                    .offset(skyv)
                    .clipped()
                    .gesture(gester(geo.size))
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(.black)
        }
        .kort()
        .onAppear {
            // Autospill: en kameraliste skal vise bilde, ikke en play-knapp.
            if spiller.currentItem == nil { spiller.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            spiller.isMuted = true      // lyd på i lista ville vært påtrengende
            spiller.play()
        }
        .onDisappear { spiller.pause() }
    }

    private func gester(_ ramme: CGSize) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { g in
                    zoom = min(max(1, zoomVedStart * g.magnification), 6)
                    skyv = klem(skyv, zoom, ramme)
                }
                .onEnded { _ in zoomVedStart = zoom },
            DragGesture()
                .onChanged { g in
                    guard zoom > 1 else { return }
                    skyv = klem(CGSize(width: skyvVedStart.width + g.translation.width,
                                       height: skyvVedStart.height + g.translation.height), zoom, ramme)
                }
                .onEnded { _ in skyvVedStart = skyv }
        )
    }

    /// Kanten skal aldri komme innenfor rammen når man drar et zoomet bilde.
    private func klem(_ s: CGSize, _ z: CGFloat, _ r: CGSize) -> CGSize {
        let mx = (z - 1) * r.width / 2, my = (z - 1) * r.height / 2
        return CGSize(width: min(max(s.width, -mx), mx), height: min(max(s.height, -my), my))
    }

    private func nullstill() { zoom = 1; zoomVedStart = 1; skyv = .zero; skyvVedStart = .zero }
}

/// Full skjerm på tvers. Her er lyden PÅ — man går i fullskjerm nettopp for å følge med.
struct Fullskjerm: View {
    let navn: String
    let url: URL
    var lukk: () -> Void

    @State private var spiller = AVPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: spiller).ignoresSafeArea()
            VStack {
                HStack {
                    Button(action: lukk) {
                        Image(systemName: "xmark")
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(navn).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.55)).clipShape(Capsule())
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            spiller.replaceCurrentItem(with: AVPlayerItem(url: url))
            spiller.isMuted = false
            spiller.play()
        }
        .onDisappear { spiller.pause() }
    }
}
