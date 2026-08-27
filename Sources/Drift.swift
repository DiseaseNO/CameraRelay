import SwiftUI

/// Driftsstatus: kjører tjenestene på serveren, og hvordan står det til med recorderen?
///
/// Hensikten er å kunne svare på «virker det?» fra sofaen. Feilsøkingsdelen over svarer på
/// om VEIEN fram er åpen; denne svarer på om det som skal kjøre i andre enden faktisk gjør
/// det, og om recorderen har plass igjen.
///
/// Recordertallene er bevisst ikke sanntid. Backend cacher dem i et minutt, og visningen
/// henter på nytt hvert minutt mens fanen er framme — hvert oppslag koster recorderen noe,
/// og det er ingenting her som endrer seg fra sekund til sekund.
struct Drift: View {
    let api: API

    @State private var data: DriftSvar?
    @State private var feil: String?
    @State private var henter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            tjenesteboks
            recorderboks
        }
        // Løkka lever så lenge visningen er synlig. Bytter man fane, kanselleres den —
        // vi poller ikke i bakgrunnen.
        .task {
            while !Task.isCancelled {
                await last()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: tjenester

    private var tjenesteboks: some View {
        boks("Tjenester på serveren", oppdatert: data?.tid) {
            if let t = data?.tjenester, !t.isEmpty {
                ForEach(t) { tj in
                    HStack(spacing: 8) {
                        Circle().fill(tj.aktiv ? Farge.ok : Farge.avvik)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tj.navn).font(.caption.weight(.medium)).foregroundStyle(Farge.tekst)
                            Text(tj.aktiv ? tj.hva : tj.tilstand)
                                .font(.caption2).foregroundStyle(tj.aktiv ? Farge.svak : Farge.avvik)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(tj.aktiv ? varighet(tj.oppeSek) : "nede")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(tj.aktiv ? Farge.dempet : Farge.avvik)
                            if tj.minneMB > 0 {
                                Text("\(tj.minneMB) MB").font(.caption2.monospacedDigit()).foregroundStyle(Farge.svak)
                            }
                        }
                    }
                }
            } else if let feil {
                Text(feil).font(.caption2).foregroundStyle(Farge.avvik)
            } else {
                Text("Henter …").font(.caption2).foregroundStyle(Farge.svak)
            }
        }
    }

    // MARK: recorder

    private var recorderboks: some View {
        boks("Recorder", oppdatert: nil) {
            if let r = data?.recorder {
                stolpe("CPU", verdi: r.cpu, tekst: "\(Int(r.cpu)) %")
                stolpe("Minne", verdi: r.minne, tekst: "\(Int(r.minne)) %")
                stolpe("Videodisk", verdi: r.videodisk.prosent,
                       tekst: "\(gb(r.videodisk.brukt)) av \(gb(r.videodisk.total))")
                Divider().overlay(Farge.strek).padding(.vertical, 2)
                rad("Plass igjen til", plassIgjen(r))
                rad("Opptak tilbake til", varighet(r.faktiskLagring) + " siden")
                rad("Oppetid", recorderOppetid(r.oppetid))
                rad("Aktive økter", "\(r.sesjoner)")
                rad("Fastvare", r.firmware.replacingOccurrences(of: "(GA), ", with: " "))
            } else if let m = data?.recorderFeil ?? feil {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                    Text(m).font(.caption2)
                }.foregroundStyle(Farge.avvik)
            } else {
                Text("Henter …").font(.caption2).foregroundStyle(Farge.svak)
            }
        }
    }

    /// Recorderens EGET anslag. Vi regnet oss tidligere fram til noe helt annet ved å
    /// dele brukt plass på oppetid — den holder ikke, for opptaksmengden varierer med
    /// hvor mye som skjer foran kameraene.
    private func plassIgjen(_ r: RecorderStatus) -> String {
        guard r.estimertLagring > 0 else { return "ukjent" }
        return "ca. " + varighet(r.estimertLagring)
    }

    // MARK: byggeklosser

    private func stolpe(_ navn: String, verdi: Double, tekst: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(navn).font(.caption).foregroundStyle(Farge.dempet)
                Spacer()
                Text(tekst).font(.caption.monospacedDigit()).foregroundStyle(Farge.tekst)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Farge.kort2)
                    Capsule().fill(farge(verdi))
                        .frame(width: max(2, geo.size.width * min(1, verdi / 100)))
                }
            }
            .frame(height: 5)
        }
    }

    /// Grønt er normalt, gult begynner å bli trangt, rødt haster. Terskler for en boks
    /// som står og filmer døgnet rundt — 60 % CPU er hverdag her, ikke en alarm.
    private func farge(_ prosent: Double) -> Color {
        prosent >= 90 ? Farge.avvik : (prosent >= 75 ? Farge.aksent : Farge.ok)
    }

    private func gb(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.0f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    /// «1 23 48 28» fra recorderen = dager timer minutter sekunder.
    private func recorderOppetid(_ rå: String) -> String {
        let d = rå.split(separator: " ").compactMap { Double($0) }
        guard d.count >= 3 else { return rå }
        return varighet(d[0] * 86400 + d[1] * 3600 + d[2] * 60)
    }

    private func varighet(_ sek: Double) -> String {
        let s = max(0, sek)
        if s >= 86400 * 60 { return String(format: "%.0f mnd", s / (86400 * 30.4)) }
        if s >= 86400 { return String(format: "%.0f d", s / 86400) }
        if s >= 3600 { return String(format: "%.0f t", s / 3600) }
        if s >= 60 { return String(format: "%.0f min", s / 60) }
        return String(format: "%.0f s", s)
    }

    private func boks<Innhold: View>(_ tittel: String, oppdatert: Double?,
                                     @ViewBuilder _ innhold: () -> Innhold) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tittel).font(.footnote.weight(.semibold)).foregroundStyle(Farge.dempet)
                Spacer()
                if oppdatert != nil {
                    Button { Task { await last() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                            .foregroundStyle(henter ? Farge.svak : Farge.aksent)
                    }
                    .disabled(henter)
                }
            }
            VStack(alignment: .leading, spacing: 8) { innhold() }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Farge.kort)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func rad(_ venstre: String, _ høyre: String) -> some View {
        HStack {
            Text(venstre).font(.caption).foregroundStyle(Farge.dempet)
            Spacer()
            Text(høyre).font(.caption.monospacedDigit()).foregroundStyle(Farge.tekst)
        }
    }

    private func last() async {
        guard !henter else { return }
        henter = true
        defer { henter = false }
        do {
            data = try await api.drift()
            feil = nil
        } catch {
            if !erAvbrutt(error) { feil = error.localizedDescription }
        }
    }
}
