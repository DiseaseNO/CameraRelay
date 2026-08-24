import AVFoundation
import SwiftUI

/// Rent videolag uten kontroller.
///
/// `VideoPlayer` fra AVKit tegner Apples egne kontroller OG fanger opp berøringer i hele
/// flaten. Det ga to problemer samtidig: dobbelt sett kontroller (Apples og våre egne), og
/// pinch-zoom som aldri nådde fram fordi overlegget spiste gesten.
///
/// `AVPlayerLayer` gir bare bildet. Da eier vi gestene selv.
struct VideoLag: UIViewRepresentable {
    let spiller: AVPlayer

    func makeUIView(context: Context) -> LagVisning {
        let v = LagVisning()
        v.backgroundColor = .black
        v.lag.player = spiller
        v.lag.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ v: LagVisning, context: Context) {
        if v.lag.player !== spiller { v.lag.player = spiller }
    }

    final class LagVisning: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var lag: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
