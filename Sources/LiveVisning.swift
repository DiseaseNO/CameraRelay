import SwiftUI
import AVKit

/// Kameraene live. Backend pakker recorderens fMP4-strøm som HLS, så AVPlayer får
/// maskinvare-dekoding, låseskjerm-kontroller og AirPlay gratis.
struct LiveVisning: View {
    let api: API
    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var valgt: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(kameraer, id: \.navn) { kam in
                            if let url = api.liveURL(kamera: kam.navn) {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Circle().fill(Farge.ok).frame(width: 7, height: 7)
                                        Text(kam.navn).foregroundStyle(Farge.tekst).font(.subheadline.weight(.medium))
                                        Spacer()
                                        Text("LIVE").font(.caption2.weight(.semibold)).foregroundStyle(Farge.ok)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)

                                    VideoPlayer(player: AVPlayer(url: url))
                                        .aspectRatio(16/9, contentMode: .fit)
                                        .background(.black)
                                }
                                .kort()
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
        }
        .task { await last() }
    }

    private func last() async {
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { feil = error.localizedDescription }
    }
}
