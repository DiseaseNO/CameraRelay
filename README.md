# CameraRelay

iPhone-app for kameraene hjemme.

## Hva appen gjør

- **Live** fra kameraene, med zoom og fullskjerm
- **Opptak** med tidslinje: bla i hendelser, spol fritt, se film-stripe per hendelse
- **Last ned** et klipp til kamerarullen
- **Lås** et klipp så det ikke blir slettet, og en egen fane for de låste
- **Drift**: om tjenestene svarer, og hvor mye plass som er igjen

Appen er bare en klient. All logikk ligger på hjemmeserveren, og det finnes ingen
adresser, nøkler eller hemmeligheter i dette repoet.

## Slik kobler du til

Passordet ditt skal aldri inn i appen. Du henter en engangskode som varer i fem
minutter, og skriver den inn sammen med serveradressen. Appen får da et enhets-token som
lagres i Keychain. Mister du telefonen, trekkes den enheten tilbake alene.

---

Oppsett, bygging og drift er dokumentert internt, ikke her.
