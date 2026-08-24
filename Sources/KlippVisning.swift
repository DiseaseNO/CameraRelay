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
    @State private var øverst: Klipp.ID?
    /// Hindrer at programstyrt rulling trigger tidslinje-flytting i loop.
    @State private var ruller = false
    /// Utsetter videobytte til rullingen har falt til ro.
    @State private var byttOppgave: Task<Void, Never>?
    @State private var fingerNede = false
    @State private var ventende: Klipp?
    @State private var fullskjerm = false
    /// Fri spoling: slipp hvor som helst og spill derfra, i stedet for å hoppe til nærmeste
    /// hendelse. Et EKSTRA valg — hendelseshopping er fortsatt standard, for det er det man
    /// vil ni ganger av ti.
    @State private var fritt = false
    @State private var friFra: Date?
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
            Tidslinje(kamera: kamera, vindu: $vindu, hode: $hode, fri: fritt) { iv in
                if fritt { friFra = hode; valgt = nil }
                else if let k = hendelser.first(where: { $0.iv.sUnix == iv.sUnix }) { velg(k) }
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
                // ScrollView framfor List: da kan vi følge hvilken hendelse som er øverst,
                // og la tidslinja gli med når man ruller. Uten det mister man
                // sammenhengen mellom lista og tiden.
                ScrollViewReader { rull in
                  ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(hendelser) { k in
                            Button { velg(k) } label: { rad(k) }
                                .id(k.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $øverst, anchor: .top)
                // Vi må vite når fingeren faktisk slipper. iOS 17 har ingen
                // scroll-fase-hendelse, så vi lytter på gesten ved siden av rullingen.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in fingerNede = true; byttOppgave?.cancel() }
                        .onEnded { _ in fingerNede = false; planleggBytte() }
                )
                .onChange(of: øverst) { _, ny in
                    guard !ruller, let id = ny, let k = hendelser.first(where: { $0.id == id }) else { return }
                    // Tidslinja følger med én gang …
                    withAnimation(.easeOut(duration: 0.2)) {
                        vindu = .init(midt: k.iv.start, spenn: vindu.spenn)
                    }
                    hode = k.iv.start
                    // … men videoen byttes IKKE mens fingeren ligger på skjermen. Den
                    // markeres blå som «hit er du på vei», og byttes først når du slipper
                    // og rullingen har falt til ro.
                    ventende = k
                    if !fingerNede { planleggBytte() }
                }
                .refreshable { await last() }
                .onChange(of: påVei?.id) { _, ny in
                    // Rull til klippet markøren står over, ellers ser man ikke hvor man
                    // er på vei — den blå rammen kan like gjerne være utenfor skjermen.
                    guard let ny else { return }
                    ruller = true
                    withAnimation(.easeOut(duration: 0.2)) { rull.scrollTo(ny, anchor: .top) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ruller = false }
                }
                }
            }
        }
    }

    /// Spilleren står ØVERST og blir stående. Trykk i lista eller på tidslinja bytter bare
    /// kilden — ingen modal som åpnes og lukkes. Det er den store forskjellen på å bla
    /// gjennom hendelser på en telefon og å åpne dem én for én.
    private var spillerFelt: some View {
        Group {
            if fritt, let fra = friFra, let url = api.friOpptakURL(kamera: kameranavn, fra: fra) {
                Spiller(url: url, markering: nil, lengde: 40)
                    .id("fri-\(Int(fra.timeIntervalSince1970))")
            } else if let k = valgt, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
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
        // simultaneousGesture, ikke gesture: som eksklusiv gest slukte den pinch-zoomen
        // inni Spiller, og zoom sluttet å virke på opptak.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { g in
                    guard abs(g.translation.width) > 70 else { return }
                    blaTil(g.translation.width < 0 ? 1 : -1)
                }
        )
        .overlay(alignment: .topTrailing) {
            if valgt != nil {
                Button { fullskjerm = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .padding(18)
            }
        }
        .fullScreenCover(isPresented: $fullskjerm) {
            if fritt, let fra = friFra, let url = api.friOpptakURL(kamera: kameranavn, fra: fra) {
                Spiller(url: url, markering: nil, lengde: 40)
                    .id("fri-\(Int(fra.timeIntervalSince1970))")
            } else if let k = valgt, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Spiller(url: url, markering: k.markering, lengde: k.iv.lengde)
                    VStack {
                        HStack {
                            Button { fullskjerm = false } label: {
                                Image(systemName: "xmark")
                                    .frame(width: 40, height: 40)
                                    .background(.black.opacity(0.55))
                                    .foregroundStyle(.white).clipShape(Circle())
                            }
                            Spacer()
                        }
                        .padding()
                        Spacer()
                    }
                }
            }
        }
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
            Button { fritt.toggle(); friFra = nil } label: {
                Label(fritt ? "Fritt" : "Hendelser", systemImage: fritt ? "slider.horizontal.3" : "figure.walk")
                    .font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(fritt ? Farge.kjol.opacity(0.22) : Farge.kort2)
                    .foregroundStyle(fritt ? Farge.kjol : Farge.dempet)
                    .clipShape(Capsule())
            }
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
                } else if erPåVei(k) {
                    Text("slipp for å spille").font(.caption2).foregroundStyle(Farge.kjol)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(Farge.kort)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(nåværende(k) ? Farge.aksent : (erPåVei(k) ? Farge.kjol : .clear),
                        lineWidth: 2)
        )
    }

    /// Hendelsen som spilles markeres — ellers mister man orienteringen når man blar.
    private func nåværende(_ k: Klipp) -> Bool { valgt?.id == k.id }

    /// Klippet markøren står over akkurat nå — altså der du lander hvis du slipper.
    /// Uten dette må man slippe for å finne ut hvor man havnet.
    private var påVei: Klipp? {
        let u = hode.timeIntervalSince1970
        return hendelser.min {
            abs($0.iv.sUnix - u) < abs($1.iv.sUnix - u)
        }.flatMap { abs($0.iv.sUnix - u) <= 300 ? $0 : nil }
    }
    private func erPåVei(_ k: Klipp) -> Bool { påVei?.id == k.id && !nåværende(k) }

    /// Bytter til den ventende hendelsen når rullingen har roet seg etter at fingeren slapp.
    /// Pausen dekker treghetsrullingen — uten den ville videoen byttet midt i utglidningen.
    private func planleggBytte() {
        byttOppgave?.cancel()
        byttOppgave = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !fingerNede, let k = ventende else { return }
            valgt = k
        }
    }

    /// Bytter kilde i spilleren og flytter spillehodet dit, så tidslinja følger med.
    private func velg(_ k: Klipp) {
        valgt = k
        hode = k.iv.start
        // Markøren står midt på tidslinja, så «gå hit» betyr å sentrere vinduet.
        withAnimation(.easeOut(duration: 0.25)) {
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
    /// Stort bilde per kamera, ikke fire små. Her skal man kjenne igjen STEDET på et blikk
    /// og velge riktig kamera — ikke studere et hendelsesforløp. Det kommer inni.
    private func rad(_ kam: KameraTL) -> some View {
        let siste = kam.deteksjonsklipp.last
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let iv = siste {
                    EnkeltRamme(api: api, klipp: Klipp(kamera: kam.navn, iv: iv, alarm: kam.alarm(i: iv)))
                } else {
                    Rectangle().fill(Farge.kort2).aspectRatio(16.0 / 9.0, contentMode: .fit)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kam.navn).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    if let iv = siste {
                        // Text(dato, format:) respekterer miljøets locale — `.formatted()`
                        // gjør det IKKE, og ga «8:01 PM» selv med nb_NO satt på appen.
                        HStack(spacing: 4) {
                            Text("siste")
                            Text(iv.start, format: .dateTime.hour().minute())
                            Text("·  \(kam.deteksjonsklipp.count) klipp")
                        }
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text("ingen klipp").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

/// Viser ÉN ramme av recorderens film-stripe, i full bredde.
///
/// Stripa er fire rammer ved siden av hverandre (~1456×200). Ved å skalere den til fire
/// ganger bredden og klippe, får vi den første rammen alene — stor nok til å kjenne igjen
/// stedet med én gang. Ingen ekstra henting: det er samme bilde som lista bruker.
struct EnkeltRamme: View {
    let api: API
    let klipp: Klipp

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: api.stripeURL(kamera: klipp.kamera,
                                          alarmUnix: (klipp.alarm ?? klipp.iv).sUnix)) { faser in
                switch faser {
                case .success(let bilde):
                    bilde.resizable().scaledToFill()
                        .frame(width: geo.size.width * 4, height: geo.size.height, alignment: .leading)
                default:
                    Rectangle().fill(Farge.kort2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
