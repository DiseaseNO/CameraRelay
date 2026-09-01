#!/usr/bin/env bash
#
# Stopper pushen hvis noe som avslører nettverket har sneket seg inn.
#
# Repoet er offentlig. En adresse, et vertsnavn eller et leverandørnavn i en kommentar er
# nok til å fortelle en fremmed hvor man banker på og hva som står bak. Kommentarer
# skrives fortløpende mens man jobber, og det er nettopp der slikt sniker seg inn igjen —
# derfor er dette en maskinsjekk og ikke en huskeregel.
#
# Mønstrene under er MED VILJE generelle. En liste over akkurat de leverandørene vi
# bruker ville selv vært en lekkasje, så leverandørsjekken nevner mange og røper dermed
# ingen.
set -uo pipefail

# Filer sjekken ikke kan lese uten å treffe seg selv.
UNNTAK='^(scripts/hygienesjekk\.sh|\.git/)'

# Ting som SKAL kunne stå: bundle-ID-er (omvendt domene), Apple og GitHub.
TILLATT='no\.gustavs1\.[a-z]+|com\.apple\.|developer\.apple\.com|api\.github\.com|github\.com|help\.apple\.com'

funn=0
sjekk() {
  local navn="$1" monster="$2"
  local treff
  treff=$(git ls-files | grep -Ev "$UNNTAK" | xargs -r grep -EnI "$monster" 2>/dev/null \
          | grep -Ev "$TILLATT" || true)
  if [ -n "$treff" ]; then
    echo "::error::$navn"
    echo "$treff" | head -20
    funn=1
  fi
}

# IP-adresser. Også 127.0.0.1 — et eksempel med loopback røper likevel oppsettet rundt.
sjekk "IP-adresse i repoet" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'

# Vertsnavn: minst to punktum og en TLD-lignende ende.
sjekk "Vertsnavn i repoet" '\b[a-z0-9-]+(\.[a-z0-9-]+){1,}\.(no|com|net|org|io|local)\b'

# Nettverks- og infrastrukturbegreper som avslører topologi.
sjekk "Infrastruktur nevnt" '\bVLAN\b|\bCT ?[0-9]{3}\b|\bLXC\b|\bsystemd\b|reverse[ -]?proxy|\bNVR\b|\bRTSP\b'

# Leverandører. Lang liste med vilje — hvem som står her røper ikke hvem vi bruker.
sjekk "Leverandørnavn nevnt" '\bForti[A-Za-z]*|\bCisco\b|\bJuniper\b|\bUbiquiti\b|\bUniFi\b|\bPalo ?Alto\b|\bSynology\b|\bQNAP\b|\bProxmox\b|\bVMware\b|\bTP-?Link\b|\bMikroTik\b|\bHikvision\b|\bDahua\b|\bAxis Communications\b'

if [ "$funn" -ne 0 ]; then
  cat <<'HJELP'

Dette repoet er offentlig. Fjern det som ble funnet, eller skriv det om slik at det
beskriver HVA noe gjør uten å si HVOR det står eller HVA det kjører på.

Hører opplysningen hjemme et sted, hører den hjemme i det interne repoet.
HJELP
  exit 1
fi
echo "hygienesjekk: ingenting å bemerke"
