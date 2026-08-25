import SwiftUI
import AVKit

/// Kameraene live. Backend pakker recorderens fMP4-strøm som HLS, så AVPlayer får
/// maskinvare-dekoding, låseskjerm-kontroller og AirPlay gratis.
struct LiveVisning: View {
    let api: API
    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var fullskjerm: String?
    /// Bumpes ved dra-ned. Brukes som `.id` på kortene, så spillerne bygges helt på nytt —
    /// å bare hente kameralista igjen hjelper ikke når det er STRØMMEN som har hengt seg.
    @State private var generasjon = 0


    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(kameraer, id: \.navn) { kam in
                            if let url = api.liveURL(kamera: kam.navn) {
                                LiveKort(navn: kam.navn, url: url, kamera: kam) {
                                    fullskjerm = kam.navn
                                }
                                    .id("\(kam.navn)-\(generasjon)")
                            }
                        }
                        if let feil {
                            Text(feil).font(.footnote).foregroundStyle(Farge.avvik).padding()
                        }
                    }
                    .padding(12)
                }
                .refreshable { generasjon += 1; await last() }
            }
            .navigationTitle("Live")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .fullScreenCover(item: Binding(
                get: { fullskjerm.map(Navn.init) },
                set: { fullskjerm = $0?.rawValue }
            )) { n in
                if let url = api.liveURL(kamera: n.rawValue) {
                    Fullskjerm(navn: n.rawValue, url: url,
                               kamera: kameraer.first { $0.navn == n.rawValue }) { fullskjerm = nil }
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
    let kamera: KameraTL
    var påFullskjerm: () -> Void

    @State private var spiller = AVPlayer()
    @State private var sisteTid: Double = -1
    @State private var stilleSiden = Date()
    @State private var vakt: Timer?
    @State private var stopp = false
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
                VideoLag(spiller: spiller)
                    .scaleEffect(zoom)
                    .offset(skyv)
                    .clipped()
                    // highPriority: uten dette vinner ScrollViewens egen dra-gest, og
                    // knipingen nådde aldri fram. Det var derfor zoom ikke virket på live.
                    .highPriorityGesture(gester(geo.size))
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(.black)
        }
        .kort()
        .overlay(alignment: .center) {
            if stopp {
                VStack(spacing: 6) {
                    ProgressView().tint(.white)
                    Text("kobler til igjen …").font(.caption2).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .onAppear { start(); startVakt() }
        .onDisappear { vakt?.invalidate(); vakt = nil; spiller.pause() }
    }

    private func start() {
        spiller.replaceCurrentItem(with: AVPlayerItem(url: url))
        spiller.isMuted = true      // lyd på i lista ville vært påtrengende
        spiller.play()
        sisteTid = -1
        stilleSiden = Date()
        stopp = false
    }

    /// Vaktbikkje. AVPlayer stopper STILLE når strømmen ryker — recorderen bytter temp-fil
    /// ved ny sesjon, og da fryser bildet eller blir svart uten at det kommer en feil.
    /// Står avspillingen i ro i 12 s, bygger vi strømmen opp igjen.
    private func startVakt() {
        vakt?.invalidate()
        vakt = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            let nå = spiller.currentTime().seconds
            let gikkFramover = nå.isFinite && nå > sisteTid + 0.2
            if gikkFramover {
                sisteTid = nå
                stilleSiden = Date()
                if stopp { stopp = false }
            } else if Date().timeIntervalSince(stilleSiden) > 12 {
                stopp = true
                start()
            }
        }
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
    /// Trengs for å finne nyeste ferdige 4K-opptak. Live er 720p transkodet av recorderen.
    var kamera: KameraTL?
    var lukk: () -> Void

    @State private var spiller = AVPlayer()
    @State private var dempet = false
    @State private var dra: CGFloat = 0
    @State private var firK = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoLag(spiller: spiller).ignoresSafeArea()
                .offset(y: dra)
                .gesture(
                    // Dra ned for å lukke — samme bevegelse som i Bilder og de fleste
                    // fullskjermvisninger på iOS.
                    DragGesture()
                        .onChanged { g in dra = max(0, g.translation.height) }
                        .onEnded { g in
                            if g.translation.height > 120 { lukk() }
                            else { withAnimation(.easeOut(duration: 0.2)) { dra = 0 } }
                        }
                )
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
                    if firKilde != nil {
                        Button {
                            firK.toggle()
                            bytt()
                        } label: {
                            Text(firK ? "720p" : "4K")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(firK ? Farge.ok : Farge.aksent)
                                .clipShape(Capsule())
                        }
                    }
                    Button {
                        dempet.toggle(); spiller.isMuted = dempet
                    } label: {
                        Image(systemName: dempet ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.55))
                            .foregroundStyle(dempet ? .white.opacity(0.6) : .white)
                            .clipShape(Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear { bytt() }
        .onDisappear { spiller.pause() }
    }

    /// Ekte 4K i sanntid, ikke et opptak. Backend spinner opp en RTSP-remux ved behov og
    /// river den når ingen henter segmenter — derfor er den bare tilgjengelig herfra, i
    /// fullskjerm, og ikke som en knapp i lista.
    private var firKilde: URL? {
        API.delt?.live4kURL(kamera: kamera?.navn ?? navn)
    }

    private func bytt() {
        let kilde = firK ? (firKilde ?? url) : url
        spiller.replaceCurrentItem(with: AVPlayerItem(url: kilde))
        spiller.isMuted = dempet   // lyd PÅ i fullskjerm — man går hit for å følge med
        spiller.play()
    }
}
