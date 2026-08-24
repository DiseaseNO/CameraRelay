import SwiftUI
import AVFoundation

@main
struct CameraRelayApp: App {
    @State private var api = API()

    init() {
        // Lyd skal spille selv om ringelyd-bryteren står på stille — man ser på kamera
        // nettopp fordi man vil høre hva som skjer.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if api.erKlar { Hovedvisning(api: api) } else { Paring(api: api) }
            }
            .preferredColorScheme(.dark)
            .tint(Farge.aksent)
        }
    }
}

struct Hovedvisning: View {
    let api: API
    var body: some View {
        TabView {
            LiveVisning(api: api)
                .tabItem { Label("Live", systemImage: "video") }
            KlippVisning(api: api)
                .tabItem { Label("Opptak", systemImage: "clock.arrow.circlepath") }
            Innstillinger(api: api)
                .tabItem { Label("Innstillinger", systemImage: "gearshape") }
        }
    }
}
