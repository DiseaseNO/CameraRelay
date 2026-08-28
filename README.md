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
export DEVELOPMENT_TEAM=DIN_TEAM_ID      # fra Apple Developer → Membership
xcodegen generate
open CameraRelay.xcodeproj
```

Legg gjerne `export DEVELOPMENT_TEAM=…` i `.envrc` eller `~/.zshrc` så slipper du å tenke på det.

### Bygge med egen Apple-konto

Prosjektet har ingenting personlig hardkodet. Skal du bruke det selv, endrer du to ting:

| Hva | Hvor |
|---|---|
| `DEVELOPMENT_TEAM` | miljøvariabel (lokalt) / `APPLE_TEAM_ID`-secret (CI) |
| `PRODUCT_BUNDLE_IDENTIFIER` | `project.yml` — må matche din egen app i App Store Connect |

Merk at `CFBundleDisplayName` (navnet under ikonet) må være **unikt på App Store**. Apple
avviser opplastingen med ITMS-90129 hvis det kolliderer med en eksisterende app — «Camera»
går for eksempel ikke.

## CI

`.github/workflows/testflight.yml` har to jobber:

- **`simulator`** kjører ved hver push: bygger, starter appen og laster opp skjermbilder.
- **`build`** laster til TestFlight, men bare ved `workflow_dispatch` eller en tag.
  Grunnen: under designarbeid bygger man mange ganger i timen, og Apple struper
  opplastinger per app. Nødvendige repository secrets:

| Secret | Hva |
|---|---|
| `APPLE_TEAM_ID` | Team ID fra Apple Developer → Membership |
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

## Versjonering — bump FØR hver TestFlight-opplasting

**Regel: hver gang det pushes en ny endring til TestFlight, økes `MARKETING_VERSION` i
`project.yml`.** Ett sted, én linje — `CFBundleShortVersionString` følger med automatisk.

Størrelsen på endringen avgjør hvilket tall som økes:

| Endring | Eksempel | Bump |
|---|---|---|
| Feilretting, justering av utseende | svarte kanter, hakkete rulling, feil farge | **patch** — 1.0.1 → 1.0.2 |
| Ny funksjon, eller noe merkbart nytt i bruk | ny fane, live 4K, ny gest | **minor** — 1.0.2 → 1.1 |
| Appen gjør noe vesentlig annet enn før | omlegging av navigasjon eller datamodell | **major** — 1.1 → 2.0 |

Er du i tvil mellom to nivåer, velg det laveste. Det koster ingenting å bumpe ofte.

**Byggnummeret skal du ALDRI røre.** `CFBundleVersion` settes fra `github.run_number` og
stiger av seg selv. Apple krever bare at det er høyere enn forrige opplasting — det var
derfor #82 kunne lastes opp rett etter at #55 traff opplastingsgrensa.

Hvorfor dette er verdt bryet: TestFlight grupperer bygg under versjonen. Uten bumping havner
alt under «1.0», og du kan ikke se hvilket bygg som inneholder hva. Med bumping ser du det
i lista.

Status: **1.3.1 = bygg 111** (28.08.2026) — kameravelgeren viser ramme 3 av film-stripa
(ramme 1 er 10 s før bevegelsen, altså tom med vilje) og henter bildet fra et klipp som er
minst fem minutter gammelt. (1.3 = bygg 107: Innstillinger ryddet til undermenyer.)
(1.2.1 = bygg 104: driftsstatus flyttet til `/api/kamera/drift`. 1.2 = bygg 101:
driftsstatus. 1.1.1 = bygg 98: handlinger i nedtrekksmeny + bekreftelse før opplåsing.
1.1 = bygg 95: nedlasting til kamerarull, låsing, fanen «Låste».) Neste opplasting skal
ha nytt versjonsnummer.

> **Nye API-stier appen bruker må ligge under `/api/kamera/`.** Utenfra går appen via
> `frcr.gustavs1.no`, der FortiADC bare slipper gjennom `^/api/kamera/`, `/api/enheter/par`
> og `/api/health`. Alt annet dropper med 503 — og feilen viser seg BARE utenfor
> hjemmenettet, aldri under intern testing. Se `smarthus/deploy/README.md`.
