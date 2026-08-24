# CameraRelay

iPhone-app for kameraene hjemme. Live og opptak fra en FortiRecorder — uten
leverandørens egen app, og uten VPN.

Appen er **bare en klient**. All tung logikk (relay mot recorderen, tidslinje,
opptaksoppslag, HLS-innpakning) ligger i smarthus-backend. Derfor finnes det ingen
adresser, IP-er eller nøkler i dette repoet.

## Slik kobler du til

Passordet ditt skal aldri inn i appen:

1. Åpne smarthus-dashbordet på hjemmenettet → **Admin → Enheter → Ny enhet**
2. Du får en **6-sifret kode som varer i 5 minutter**
3. Skriv inn serveradressen og koden i appen

Appen får da et **enhets-token** som lagres i Keychain og sendes som
`Authorization: Bearer`. Tokenet kan trekkes tilbake enkeltvis fra dashbordet —
mister du telefonen, er det én knapp.

## Bygge lokalt

Xcode-prosjektet er **generert**, ikke sjekket inn. Det holder prosjektfila fri for
merge-konflikter og gjør at CI bygger fra nøyaktig samme kilde som du.

```bash
brew install xcodegen
xcodegen generate
open CameraRelay.xcodeproj
```

## CI

`.github/workflows/testflight.yml` bygger på `macos`-runner og laster til TestFlight
ved push til `main`. Nødvendige repository secrets:

| Secret | Hva |
|---|---|
| `APPLE_TEAM_ID` | Team ID fra Apple Developer |
| `ASC_KEY_ID` | Key ID for App Store Connect API-nøkkelen |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8_BASE64` | `.p8`-fila, base64-kodet (`base64 -i AuthKey_XXX.p8`) |

## Capabilities

**Ingen.** Appen trenger verken push, app groups, keychain sharing eller associated domains.
Bakgrunnslyd (som også gir Picture-in-Picture) settes i Info.plist via `project.yml`, ikke som
entitlement. Vanlig HTTPS krever ingen capability — og siden serveren har et ekte
Let's Encrypt-sertifikat trengs heller ingen App Transport Security-unntak.

## Teknisk

AVPlayer kan ikke MediaSource Extensions, som web-dashbordet bruker. Backend pakker
derfor den samme fMP4-strømmen som HLS (`EXT-X-MAP` + `EXT-X-BYTERANGE`) — ingen
transkoding, samme byte-ranges, ingen ekstra last på recorderen.

| Endepunkt | Brukes til |
|---|---|
| `POST /api/enheter/par` | paring, eneste åpne endepunkt |
| `GET /api/kamera/tidslinje` | kameraliste, klipp og hendelser |
| `GET /api/kamera/:navn/live.m3u8` | live (720p H.264) |
| `GET /api/kamera/:navn/opptak.m3u8` | opptak (4K HEVC) |
| `GET /api/kamera/:navn/bilde` | film-stripe per hendelse |
