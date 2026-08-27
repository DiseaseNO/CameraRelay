import Foundation
import Photos
import Observation

/// Laster et klipp ned og legger det i KAMERARULLEN.
///
/// To ting må stemme for at Fotos skal godta fila, og begge var feil i recorderens
/// original: den er en fragmentert MP4 tagget `hev1`. Backend pakker den derfor om til en
/// vanlig progressiv MP4 med `hvc1` (`-c copy`, ingen reenkoding). Her gjenstår bare å
/// hente den og be om skrive-tilgang.
///
/// Vi ber om `.addOnly`. Appen skal legge TIL bilder, ikke lese biblioteket — da slipper
/// brukeren en tilgangsforespørsel som er større enn behovet.
/// `@MainActor` ligger på METODENE, ikke på klassen. En hel-isolert klasse kan ikke
/// opprettes fra en `@State`-initialisator (den er ikke isolert), mens metode-isolering
/// gir akkurat den garantien vi trenger: `@Observable`-tilstand endres bare på hovedtråden.
/// Det var nettopp bakgrunnstråd-endring av en `@Observable` som fikk tidslinja til å hakke.
@Observable
final class Nedlaster {
    enum Tilstand: Equatable {
        case klar
        case laster
        case ferdig
        case feil(String)
    }

    private(set) var tilstand: Tilstand = .klar
    var laster: Bool { tilstand == .laster }

    /// Melding som skal vises til brukeren, eller nil når det ikke er noe å si.
    var melding: String? {
        switch tilstand {
        case .klar, .laster: nil
        case .ferdig:        "Lagret i kamerarullen"
        case .feil(let m):   m
        }
    }

    @MainActor func nullstill() { tilstand = .klar }

    @MainActor func lastNed(api: API, kamera: String, klipp: Intervall, sub: Int = 2) async {
        guard tilstand != .laster else { return }
        tilstand = .laster
        do {
            guard await beOmTilgang() else {
                tilstand = .feil("Appen får ikke lagre i Fotos. Slå på tilgang i Innstillinger.")
                return
            }
            let fil = try await api.lastNedKlipp(kamera: kamera, klipp: klipp, sub: sub)
            // Rydd uansett hvordan det går — et 4K-klipp er titalls MB, og temp-mappa
            // tømmes ikke av seg selv mens appen lever.
            defer { try? FileManager.default.removeItem(at: fil) }
            try await lagre(fil)
            tilstand = .ferdig
        } catch {
            tilstand = erAvbrutt(error) ? .klar : .feil(error.localizedDescription)
        }
    }

    @MainActor private func beOmTilgang() async -> Bool {
        let nå = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if nå == .authorized || nå == .limited { return true }
        if nå == .denied || nå == .restricted { return false }
        let svar = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return svar == .authorized || svar == .limited
    }

    private nonisolated func lagre(_ fil: URL) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let rq = PHAssetCreationRequest.forAsset()
            let valg = PHAssetResourceCreationOptions()
            valg.shouldMoveFile = false
            rq.addResource(with: .video, fileURL: fil, options: valg)
        }
    }
}
