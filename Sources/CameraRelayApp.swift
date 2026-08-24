import SwiftUI
import AVFoundation

#if DEBUG
/// Testvei for simulator i CI: oppstartsargumentene `-server <vert> -token <tok>` legges
/// rett i Keychain, så vi kommer forbi paringsskjermen og kan skjermbilde resten av appen.
///
/// Kompileres KUN inn i DEBUG. TestFlight- og App Store-byggene er Release og inneholder
/// ikke denne koden — det finnes altså ingen omvei rundt paringen i det du installerer.
/// (UserDefaults plukker opp `-nøkkel verdi`-argumenter av seg selv.)
private func seedFraOppstartsargumenter() {
    let d = UserDefaults.standard
    guard let vert = d.string(forKey: "server"), !vert.isEmpty,
          let token = d.string(forKey: "token"), !token.isEmpty else { return }
    Nøkkelring.skriv(vert, for: "vert")
    Nøkkelring.skriv(token, for: "token")
}
#endif

@main
struct CameraRelayApp: App {
    @State private var api: API

    init() {
        #if DEBUG
        seedFraOppstartsargumenter()   // må skje FØR API() leser Keychain
        #endif
        _api = State(initialValue: API())

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
