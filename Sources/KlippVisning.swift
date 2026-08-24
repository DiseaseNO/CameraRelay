import SwiftUI

/// Opptak: kameravelger, dato, tidslinje med spillehode, og hendelseslista under.
///
/// Oppbygningen låner fra Tapo der de har løst det bedre enn min første versjon:
/// tidslinja viser hvor du er (spillehode + tidsboble), datoen velges med piler i stedet
/// for endeløs panorering, varigheten ligger oppå miniatyren for å spare bredde, og det
/// som spilles er markert i lista så man ikke mister orienteringen.
///
/// Én ting gjør vi tydeligere enn dem: kamera velges eksplisitt. Med to kameraer på samme
/// tidslinje blir strekene meningsløse — de ville kommet fra to forskjellige steder.
struct KlippVisning: View {
    let api: API

    @State private var kameraer: [KameraTL] = []
    @State private var valgtKamera: String?
    @State private var dag: Date = Calendar.current.startOfDay(for: .now)
    @State private var vindu = Tidslinje.Vindu(midt: .now, spenn: 3 * 3600)
    @State private var hode: Date = .now
    @State private var spiller: IntPakke?
    @State private var feil: String?
    @State private var laster = true

    private var kamera: KameraTL? {
        kameraer.first { $0.navn == valgtKamera } ?? kameraer.first
    }

    /// Hendelsene på valgt dag, nyest først. Dette er også rekkefølgen spilleren blar i.
    private var hendelser: [Klipp] {
        guard let kam = kamera else { return [] }
        let start = dag, slutt = dag.addingTimeInterval(86400)
        return kam.deteksjonsklipp
            .filter { $0.start >= start && $0.start < slutt }
            .map { Klipp(kamera: kam.navn, iv: $0, alarm: kam.alarm(i: $0)) }
            .sorted { $0.iv.sUnix > $1.iv.sUnix }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                if laster && kameraer.isEmpty {
                    ProgressView().tint(Farge.dempet)
                } else if let feil, kameraer.isEmpty {
                    VStack(spacing: 10) {
                        Text(feil).foregroundStyle(Farge.avvik).multilineTextAlignment(.center)
                        Button("Prøv igjen") { Task { await last() } }.foregroundStyle(Farge.aksent)
                    }.padding()
                } else {
                    innhold
                }
            }
            .navigationTitle("Opptak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .fullScreenCover(item: $spiller) { p in
                SpillerSkjerm(api: api, klipp: hendelser, start: p.verdi)
            }
        }
        .task { await last() }
    }

    private var innhold: some View {
        VStack(spacing: 0) {
            kameravelger
            datolinje
            Tidslinje(kamera: kamera, vindu: $vindu, hode: $hode) { iv in
                if let i = hendelser.firstIndex(where: { $0.iv.sUnix == iv.sUnix }) {
                    spiller = IntPakke(verdi: i)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            HStack {
                Text("Oppdagede hendelser (\(hendelser.count))")
                    .font(.footnote.weight(.medium)).foregroundStyle(Farge.dempet)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.bottom, 6)

            if hendelser.isEmpty {
                Spacer()
                Text("Ingen hendelser denne dagen.").font(.subheadline).foregroundStyle(Farge.svak)
                Spacer()
            } else {
                List(Array(hendelser.enumerated()), id: \.element.id) { i, k in
                    Button { spiller = IntPakke(verdi: i) } label: { rad(k) }
                        .listRowBackground(Farge.flate)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await last() }
            }
        }
    }

    private var kameravelger: some View {
        Picker("Kamera", selection: Binding(
            get: { valgtKamera ?? kameraer.first?.navn ?? "" },
            set: { valgtKamera = $0 }
        )) {
            ForEach(kameraer, id: \.navn) { Text($0.navn).tag($0.navn) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var datolinje: some View {
        HStack(spacing: 14) {
            Button { flyttDag(-1) } label: { Image(systemName: "chevron.left") }
                .foregroundStyle(Farge.dempet)
            Text(dag, format: .dateTime.day().month(.wide).year())
                .font(.subheadline.weight(.medium)).foregroundStyle(Farge.tekst)
            Button { flyttDag(1) } label: { Image(systemName: "chevron.right") }
                .foregroundStyle(erIdag ? Farge.strek : Farge.dempet)
                .disabled(erIdag)
            Spacer()
            Button("Nå") { gåTilNå() }
                .font(.caption).foregroundStyle(Farge.aksent)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    /// Miniatyr med varigheten oppå — sparer en hel kolonne på en smal skjerm.
    private func rad(_ k: Klipp) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Stripe(api: api, klipp: k)
                    .frame(width: 132, height: 46)
                Text(varighet(k.iv))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(.black.opacity(0.65))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(3)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(k.iv.start, format: .dateTime.hour().minute().second())
                    .font(.headline.monospacedDigit()).foregroundStyle(Farge.tekst)
                Image(systemName: "figure.walk")
                    .font(.caption).foregroundStyle(Farge.aksent)
            }
            Spacer()
        }
        .padding(6)
        .background(Farge.kort)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(nåværende(k) ? Farge.aksent : .clear, lineWidth: 2)
        )
    }

    /// Hendelsen spillehodet står på markeres — ellers mister man orienteringen når man blar.
    private func nåværende(_ k: Klipp) -> Bool {
        let u = hode.timeIntervalSince1970
        return u >= k.iv.sUnix - 1 && u <= k.iv.eUnix + 1
    }

    private var erIdag: Bool {
        Calendar.current.isDate(dag, inSameDayAs: .now)
    }

    private func flyttDag(_ n: Int) {
        guard let ny = Calendar.current.date(byAdding: .day, value: n, to: dag) else { return }
        dag = ny
        let midt = Calendar.current.isDate(ny, inSameDayAs: .now)
            ? Date.now
            : ny.addingTimeInterval(12 * 3600)
        vindu = .init(midt: midt, spenn: vindu.spenn)
        hode = midt
    }

    private func gåTilNå() {
        dag = Calendar.current.startOfDay(for: .now)
        vindu = .init(midt: .now, spenn: vindu.spenn)
        hode = .now
    }

    private func varighet(_ iv: Intervall) -> String {
        let d = Int(iv.lengde.rounded())
        return String(format: "%d:%02d", d / 60, d % 60)
    }

    private func last() async {
        laster = kameraer.isEmpty
        defer { laster = false }
        do {
            kameraer = try await api.tidslinje()
            if valgtKamera == nil { valgtKamera = kameraer.first?.navn }
            feil = nil
        } catch {
            feil = error.localizedDescription
        }
    }
}

// MARK: - byggeklosser

struct Klipp: Identifiable {
    let kamera: String
    let iv: Intervall
    let alarm: Intervall?
    var id: String { "\(kamera)-\(Int(iv.sUnix))" }

    /// Alarmvinduet i sekunder fra klippets start — det gule feltet i spillerens bar.
    var markering: (fra: Double, til: Double)? {
        guard let a = alarm else { return nil }
        let fra = max(0, a.sUnix - iv.sUnix)
        return (fra, max(fra + 1, a.eUnix - iv.sUnix))
    }
}

/// Recorderens film-stripe: fire rammer i én JPEG. Vises HEL — beskjærer man den til
/// 16:9 ser man bare en flis av hendelsen, og da er den verdiløs.
struct Stripe: View {
    let api: API
    let klipp: Klipp

    var body: some View {
        AsyncImage(url: api.stripeURL(kamera: klipp.kamera,
                                      alarmUnix: (klipp.alarm ?? klipp.iv).sUnix)) { faser in
            switch faser {
            case .success(let bilde): bilde.resizable().scaledToFill()
            default: Rectangle().fill(Farge.kort2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Liten innpakning så en indeks kan brukes med `.fullScreenCover(item:)`.
struct IntPakke: Identifiable {
    let verdi: Int
    var id: Int { verdi }
}
