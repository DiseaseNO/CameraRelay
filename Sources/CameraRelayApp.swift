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
    let vert = d.string(forKey: "server") ?? ""
    let token = d.string(forKey: "token") ?? ""
    NSLog("CR-SEED: argumenter=\(ProcessInfo.processInfo.arguments.count) vert=\(vert.isEmpty ? "TOM" : vert) token=\(token.isEmpty ? "TOM" : "\(token.count) tegn")")
    guard !vert.isEmpty, !token.isEmpty else { return }
    Nøkkelring.skriv(vert, for: "vert")
    Nøkkelring.skriv(token, for: "token")
    NSLog("CR-SEED: skrevet. Lest tilbake: vert=\(Nøkkelring.les("vert") ?? "nil") token=\(Nøkkelring.les("token") != nil ? "ok" : "nil")")
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
            // Appen er på norsk; da skal klokkeslett og datoer være det også.
            // Uten dette arver den enhetens locale og viser «7:36:23 PM».
            .environment(\.locale, Locale(identifier: "nb_NO"))
        }
    }
}

struct Hovedvisning: View {
    let api: API
    @State private var fane = 0

    init(api: API) {
        self.api = api
        #if DEBUG
        // Lar simulator-testene starte rett på en gitt fane: `-startfane opptak`.
        // Uten dette ser vi bare Live, siden simulatoren ikke kan trykke.
        if UserDefaults.standard.string(forKey: "startfane") == "opptak" { _fane = State(initialValue: 1) }
        #endif
    }

    var body: some View {
        TabView(selection: $fane) {
            LiveVisning(api: api)
                .tabItem { Label("Live", systemImage: "video") }.tag(0)
            Kameraliste(api: api)
                .tabItem { Label("Opptak", systemImage: "clock.arrow.circlepath") }.tag(1)
            LåsteVisning(api: api)
                .tabItem { Label("Låste", systemImage: "lock.fill") }.tag(2)
            Innstillinger(api: api)
                .tabItem { Label("Innstillinger", systemImage: "gearshape") }.tag(3)
        }
    }
}
