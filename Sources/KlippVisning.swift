import SwiftUI

/// Opptak for ETT kamera: dato, tidslinje med spillehode, og hendelseslista under.
///
/// Kameraet velges FØR man kommer hit (se `Kameraliste`) — samme flyt som Tapo. Da slipper
/// vi en velger som stjeler høyde, og tidslinja får all plassen den trenger.
///
/// Resten låner fra Tapo der de løste det bedre enn mitt første forsøk: tidslinja viser hvor
/// du er (spillehode + tidsboble), datoen velges med piler i stedet for endeløs panorering,
/// varigheten ligger oppå miniatyren for å spare bredde, og hendelsen som spilles er markert
/// så man ikke mister orienteringen.
struct KameraOpptak: View {
    let api: API
    let kameranavn: String

    @State private var kameraer: [KameraTL] = []
    @State private var dag: Date = Calendar.current.startOfDay(for: .now)
    // 1 time som utgangspunkt: i et 3-timers vindu blir et 40-sekunders klipp
    // drøyt ett punkt bredt, og da ser alle hendelser like lange ut.
    @State private var vindu = Tidslinje.Vindu(midt: .now, spenn: 3600)
    @State private var hode: Date = .now
    @State private var valgt: Klipp?
    @State private var feil: String?
    @State private var laster = true

    private var kamera: KameraTL? { kameraer.first { $0.navn == kameranavn } }

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
        .navigationTitle(kameranavn)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Farge.flate, for: .navigationBar)
        .task { await last() }
    }

    private var innhold: some View {
        VStack(spacing: 0) {
            spillerFelt
            datolinje
            Tidslinje(kamera: kamera, vindu: $vindu, hode: $hode) { iv in
                if let k = hendelser.first(where: { $0.iv.sUnix == iv.sUnix }) { velg(k) }
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
                List(hendelser) { k in
                    Button { velg(k) } label: { rad(k) }
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

    /// Spilleren står ØVERST og blir stående. Trykk i lista eller på tidslinja bytter bare
    /// kilden — ingen modal som åpnes og lukkes. Det er den store forskjellen på å bla
    /// gjennom hendelser på en telefon og å åpne dem én for én.
    private var spillerFelt: some View {
        Group {
            if let k = valgt, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
                // IKKE tving 16:9 på hele feltet: kontrollbaren ligger inni Spiller, og da
                // måtte bildet krympe for å gi plass — resultatet var svarte kanter på
                // sidene. Spiller styrer selv bildets sideforhold.
                Spiller(url: url, markering: k.markering, lengde: k.iv.lengde)
                    .id(k.id)   // ny spiller per klipp — ellers henger forrige igjen
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.black)
                    if hendelser.isEmpty {
                        Text("Ingen opptak å vise").font(.footnote).foregroundStyle(Farge.svak)
                    } else {
                        ProgressView().tint(Farge.dempet)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        // Sveip til neste/forrige hendelse uten å se ned i lista. Romslig terskel (70 pt),
        // for pinch-zoom i bildet bruker samme flate.
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { g in
                    guard abs(g.translation.width) > 70 else { return }
                    blaTil(g.translation.width < 0 ? 1 : -1)
                }
        )
    }

    /// +1 = eldre hendelse (lista er nyest først), -1 = nyere.
    private func blaTil(_ retning: Int) {
        guard let n = valgt, let i = hendelser.firstIndex(where: { $0.id == n.id }) else { return }
        let mål = i + retning
        if hendelser.indices.contains(mål) { velg(hendelser[mål]) }
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

    /// Rad: film-stripa i FULL BREDDE øverst, metadata under.
    ///
    /// Stripa er fire rammer ved siden av hverandre, altså ~7:1. I en smal kolonne ble
    /// bare halvparten synlig, og da mister den verdien sin — poenget er nettopp å se
    /// forløpet uten å spille av.
    private func rad(_ k: Klipp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Stripe(api: api, klipp: k)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1456.0 / 200.0, contentMode: .fit)
                Text(varighet(k.iv))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
            HStack(spacing: 8) {
                Image(systemName: "figure.walk").font(.caption2).foregroundStyle(Farge.aksent)
                Text(k.iv.start, format: .dateTime.hour().minute().second())
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Farge.tekst)
                Spacer()
                if nåværende(k) {
                    Text("spilles").font(.caption2).foregroundStyle(Farge.aksent)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(Farge.kort)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(nåværende(k) ? Farge.aksent : .clear, lineWidth: 2)
        )
    }

    /// Hendelsen som spilles markeres — ellers mister man orienteringen når man blar.
    private func nåværende(_ k: Klipp) -> Bool { valgt?.id == k.id }

    /// Bytter kilde i spilleren og flytter spillehodet dit, så tidslinja følger med.
    private func velg(_ k: Klipp) {
        valgt = k
        hode = k.iv.start
        if k.iv.start < vindu.fra || k.iv.start > vindu.til {
            vindu = .init(midt: k.iv.start, spenn: vindu.spenn)
        }
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
            feil = nil
            // Start på nyeste hendelse — en tom spiller er ingen god førsteopplevelse.
            if valgt == nil, let første = hendelser.first { velg(første) }
        } catch {
            feil = error.localizedDescription
        }
    }
}

/// Opptak-fanens rot: velg kamera, og gå inn i det kameraets opptak.
struct Kameraliste: View {
    let api: API
    @State private var kameraer: [KameraTL] = []
    @State private var feil: String?
    @State private var sti: [String] = []

    var body: some View {
        NavigationStack(path: $sti) {
            ZStack {
                Farge.flate.ignoresSafeArea()
                if kameraer.isEmpty {
                    if let feil {
                        Text(feil).foregroundStyle(Farge.avvik).padding()
                    } else {
                        ProgressView().tint(Farge.dempet)
                    }
                } else {
                    List(kameraer, id: \.navn) { kam in
                        NavigationLink(value: kam.navn) { rad(kam) }
                        .listRowBackground(Farge.kort)
                        .listRowSeparatorTint(Farge.strek)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await last() }
                }
            }
            .navigationTitle("Opptak")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .navigationDestination(for: String.self) { navn in
                KameraOpptak(api: api, kameranavn: navn)
            }
        }
        .task {
            await last()
            #if DEBUG
            // Simulator-testene kan gå rett inn i ett kamera: `-startkamera Gate`.
            if let k = UserDefaults.standard.string(forKey: "startkamera"),
               kameraer.contains(where: { $0.navn == k }) { sti = [k] }
            #endif
        }
    }

    /// Nyeste hendelse som forhåndsvisning — da ser du hva kameraet sist fanget uten å
    /// gå inn, og du kjenner igjen kameraet på bildet framfor navnet.
    private func rad(_ kam: KameraTL) -> some View {
        let siste = kam.deteksjonsklipp.last
        return HStack(spacing: 12) {
            if let iv = siste {
                Stripe(api: api, klipp: Klipp(kamera: kam.navn, iv: iv, alarm: kam.alarm(i: iv)))
                    .frame(width: 108, height: 40)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Farge.kort2).frame(width: 108, height: 40)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(kam.navn).font(.headline).foregroundStyle(Farge.tekst)
                if let iv = siste {
                    Text("siste: \(iv.start.formatted(.dateTime.hour().minute()))  ·  \(kam.deteksjonsklipp.count) klipp")
                        .font(.caption).foregroundStyle(Farge.dempet)
                } else {
                    Text("ingen klipp").font(.caption).foregroundStyle(Farge.svak)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func last() async {
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { feil = error.localizedDescription }
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
            // scaledToFit, ikke Fill: stripa er ~7:1 og ville flommet ut av raden og
            // lagt seg bak teksten. Den skal vises HEL — det er hele poenget med den.
            case .success(let bilde): bilde.resizable().scaledToFit()
            default: Rectangle().fill(Farge.kort2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
