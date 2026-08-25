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
                    Fullskjerm(api: api, navn: n.rawValue, url: url,
                               kamera: kameraer.first { $0.navn == n.rawValue }) { fullskjerm = nil }
                }
            }

        }
        .task { await last() }
    }

    private func last() async {
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { if !erAvbrutt(error) { feil = error.localizedDescription } }
    }

    struct Navn: Identifiable { let rawValue: String; var id: String { rawValue } }
}

/// Ett kamera i lista. Spiller AV SEG SELV med én gang — man åpner ikke en kamera-app
/// for å så måtte trykke play.
///
/// INGEN zoom her. Lista er til å se hva som skjer og velge kamera; skal man
/// granske noe, går man i fullskjerm — der har man plassen til det.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(Farge.ok).frame(width: 7, height: 7)
                Text(navn).foregroundStyle(Farge.tekst).font(.subheadline.weight(.medium))
                Spacer()
                Button(action: påFullskjerm) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote).foregroundStyle(Farge.dempet)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            // Ingen gester her: hele flaten tilhører rullingen, så dra-ned-for-
            // oppdatering virker. Utvid-knappen tar deg dit man kan granske bildet.
            VideoLag(spiller: spiller)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
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

}

/// Full skjerm på tvers. Her er lyden PÅ — man går i fullskjerm nettopp for å følge med.
struct Fullskjerm: View {
    let api: API
    let navn: String
    let url: URL
    var kamera: KameraTL?
    var lukk: () -> Void

    @State private var spiller = AVPlayer()
    @State private var zoom: CGFloat = 1
    @State private var skyv: CGSize = .zero
    @State private var zoomVedStart: CGFloat = 1
    @State private var skyvVedStart: CGSize = .zero
    /// 4K må hentes fra recorderen og pakkes om før første bilde finnes. Uten en synlig
    /// venteindikator ser knappen ut som den ikke gjorde noe.
    @State private var laster4k = false
    // Lyd AV til man ber om det. Å åpne fullskjerm skal ikke plutselig gi lyd i rommet.
    @State private var dempet = true
    @State private var dra: CGFloat = 0
    @State private var firK = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geo in
                VideoLag(spiller: spiller)
                    .scaleEffect(zoom)
                    .offset(x: skyv.width, y: skyv.height + dra)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    // Zoom manglet HELT i fullskjerm — all zoom-kode lå i kortet i lista.
                    .highPriorityGesture(
                        MagnifyGesture()
                            .onChanged { g in
                                zoom = min(max(1, zoomVedStart * g.magnification), 6)
                                skyv = klem(skyv, zoom, geo.size)
                            }
                            .onEnded { _ in zoomVedStart = zoom }
                    )
                    // Ved 1x drar man for å LUKKE. Er bildet zoomet, panorerer man i det —
                    // ellers ville hver granskning av et hjørne lukket visningen.
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { g in
                                if zoom > 1 {
                                    skyv = klem(CGSize(width: skyvVedStart.width + g.translation.width,
                                                       height: skyvVedStart.height + g.translation.height),
                                                zoom, geo.size)
                                } else {
                                    dra = max(0, g.translation.height)
                                }
                            }
                            .onEnded { g in
                                if zoom > 1 { skyvVedStart = skyv; return }
                                if g.translation.height > 120 { lukk() }
                                else { withAnimation(.easeOut(duration: 0.2)) { dra = 0 } }
                            }
                    )
            }
            .ignoresSafeArea()
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
                    if zoom > 1.02 {
                        Button { zoom = 1; zoomVedStart = 1; skyv = .zero; skyvVedStart = .zero } label: {
                            Text("\(zoom, specifier: "%.1f")×")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(.black.opacity(0.55)).foregroundStyle(Farge.aksent)
                                .clipShape(Capsule())
                        }
                    }
                    if firKilde != nil {
                        Button {
                            firK.toggle()
                            bytt()
                        } label: {
                            // Knappen viser hva du ER PÅ, ikke hva du bytter til. Den
                            // motsatte lesningen er tvetydig: «4K» kan like gjerne bety
                            // «du ser 4K» som «trykk for 4K», og da må man gjette.
                            Text(laster4k ? "…" : (firK ? "4K" : "720p"))
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .background(.black.opacity(0.55))
                                .foregroundStyle(firK ? Farge.aksent : Farge.ok)
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
    private var firKilde: URL? { api.live4kURL(kamera: kamera?.navn ?? navn) }

    private func klem(_ s: CGSize, _ z: CGFloat, _ r: CGSize) -> CGSize {
        let mx = (z - 1) * r.width / 2, my = (z - 1) * r.height / 2
        return CGSize(width: min(max(s.width, -mx), mx), height: min(max(s.height, -my), my))
    }

    private func bytt() {
        let kilde = firK ? (firKilde ?? url) : url
        // Backend må starte RTSP-uttrekket og samle tre segmenter før AVPlayer kan begynne.
        // Det tar rundt seks sekunder, og uten dette flagget ser skjermen bare død ut.
        laster4k = firK
        let vare = AVPlayerItem(url: kilde)
        spiller.replaceCurrentItem(with: vare)
        spiller.isMuted = dempet
        spiller.play()
        if firK {
            Task {
                for _ in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(400))
                    if vare.status == .failed || spiller.currentTime().seconds > 0 { break }
                }
                laster4k = false
            }
        }
    }
}
