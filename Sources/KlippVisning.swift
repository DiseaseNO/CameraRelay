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
    /// BLÅ ramme: hendelsen du har rullet fram til. Ingenting spilles av den grunn.
    @State private var valgt: Klipp?
    /// ORANSJE ramme: hendelsen som faktisk spilles. Settes KUN ved trykk.
    @State private var spilles: Klipp?
    @State private var øverst: Klipp.ID?
    /// Hindrer at programstyrt rulling trigger tidslinje-flytting i loop.
    @State private var ruller = false
    /// Hendelsene på valgt dag, hurtiglagret. Var en beregnet variabel før, og det var
    /// årsaken til hakkingen: den filtrerte, mappet og sorterte ~250 klipp på nytt hver
    /// eneste gang noe leste den — flere ganger per rullebilde.
    @State private var hendelser: [Klipp] = []
    @State private var fullskjerm = false
    /// Fri spoling: slipp hvor som helst og spill derfra, i stedet for å hoppe til nærmeste
    /// hendelse. Et EKSTRA valg — hendelseshopping er fortsatt standard, for det er det man
    /// vil ni ganger av ti.
    @State private var fritt = false
    @State private var friFra: Date?
    @State private var feil: String?
    @State private var laster = true
    /// Låste klipp for dette kameraet. Hentes med ETT kall når visningen åpnes — ikke per
    /// rad. Å slå opp låsestatus for ett klipp får recorderen til å generere klippet, så
    /// et oppslag per rad man blar forbi ville lagt den ned.
    @State private var låste: [LåstKlipp] = []
    /// Nedlasting og låsing bor i menyen øverst til høyre, ikke som knapper i kolonnen.
    /// Knappene tok høyde fra hendelseslista, og på videoflaten ville de kommet i veien
    /// for zoomen. Tittellinja hadde ingenting på høyre side fra før.
    @State private var nedlaster = Nedlaster()
    @State private var låser = false
    @State private var låsefeil: String?
    /// Klippet som venter på «ja, lås opp». Å låse opp uten å mene det er den ene
    /// handlingen her som kan miste et opptak for godt.
    @State private var bekreftOpplås: Klipp?

    private var kamera: KameraTL? { kameraer.first { $0.navn == kameranavn } }

    /// Recorderen justerer grensene på et deteksjonsklipp mens bevegelsen pågår, så det
    /// låste klippet kan ha litt andre tider enn dem vi har lagret. Vi sammenligner derfor
    /// med OVERLAPP, ikke med likhet.
    private func erLåst(_ k: Klipp) -> Bool {
        låste.contains { $0.navn == k.kamera && $0.sUnix < k.iv.eUnix + 2 && $0.eUnix > k.iv.sUnix - 2 }
    }

    /// Regner ut hendelsene på valgt dag, nyest først. Kalles når dagen eller dataene
    /// endrer seg — ikke under rulling.
    private func oppdaterHendelser() {
        guard let kam = kamera else { hendelser = []; return }
        let start = dag, slutt = dag.addingTimeInterval(86400)
        hendelser = kam.deteksjonsklipp
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) { klippmeny } }
        .confirmationDialog("Lås opp klippet?",
                            isPresented: .init(get: { bekreftOpplås != nil },
                                               set: { if !$0 { bekreftOpplås = nil } }),
                            titleVisibility: .visible) {
            Button("Lås opp", role: .destructive) {
                if let k = bekreftOpplås { Task { await settLås(k, lås: false) } }
                bekreftOpplås = nil
            }
            Button("Avbryt", role: .cancel) { bekreftOpplås = nil }
        } message: {
            Text("Da kan opptaket bli slettet når disken går full.")
        }
        .task { await last() }
    }

    /// Handlingene for klippet man ser på. Meny framfor knapper: ingen fast plass, og
    /// videoflaten holdes ren så pinch-zoom har hele bildet for seg selv.
    private var klippmeny: some View {
        Menu {
            if let k = spilles ?? valgt {
                Section(klokkeslett(k)) {
                    Button {
                        Task { await nedlaster.lastNed(api: api, kamera: k.kamera, klipp: k.iv) }
                    } label: { Label("Last ned til kamerarull", systemImage: "arrow.down.to.line") }

                    if erLåst(k) {
                        Button(role: .destructive) { bekreftOpplås = k } label: {
                            Label("Lås opp", systemImage: "lock.open")
                        }
                    } else {
                        Button { Task { await settLås(k, lås: true) } } label: {
                            Label("Lås mot sletting", systemImage: "lock")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled((spilles ?? valgt) == nil || nedlaster.laster || låser)
    }

    private func klokkeslett(_ k: Klipp) -> String {
        k.iv.start.formatted(.dateTime.hour().minute().second())
    }

    private func settLås(_ k: Klipp, lås: Bool) async {
        guard !låser else { return }
        låser = true
        låsefeil = nil
        defer { låser = false }
        do {
            _ = try await api.settLås(kamera: k.kamera, klipp: k.iv, lås: lås)
            await lastLåste()
        } catch {
            if !erAvbrutt(error) { låsefeil = error.localizedDescription }
        }
    }

    /// Kort tilbakemelding som legger seg OPPÅ bildet. Den tar ingen plass i kolonnen og
    /// slipper trykk gjennom, så den kommer verken i veien for lista eller for zoomen.
    private var statusmerke: some View {
        Group {
            if let (tekst, erFeil) = status {
                HStack(spacing: 6) {
                    if nedlaster.laster || låser {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: erFeil ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.caption2)
                    }
                    Text(tekst).font(.caption2.weight(.medium))
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.black.opacity(0.75))
                .foregroundStyle(erFeil ? Farge.avvik : .white)
                .clipShape(Capsule())
                .padding(10)
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private var status: (String, Bool)? {
        if nedlaster.laster { return ("Laster ned…", false) }
        if låser { return ("Oppdaterer lås…", false) }
        if let m = låsefeil { return (m, true) }
        if let m = nedlaster.melding { return (m, m != "Lagret i kamerarullen") }
        return nil
    }

    private var innhold: some View {
        VStack(spacing: 0) {
            // Spilleren har forrang på plassen. Uten dette gir VStacken den bare det som
            // blir til overs, og bildet krymper i bredden.
            spillerFelt.layoutPriority(1)
            datolinje
            // Å slippe tidslinja VELGER bare. Ingenting starter av seg selv — det var
            // nettopp autostarten som gjorde bladring stressende.
            Tidslinje(kamera: kamera, vindu: $vindu, hode: $hode, fri: fritt) { iv in
                if fritt { friFra = hode; valgt = nil; spilles = nil }
                else if let k = hendelser.first(where: { $0.iv.sUnix == iv.sUnix }) { velg(k) }
            } påTrykk: {
                // Trykk på tidslinja spiller det som er valgt.
                if fritt, påDekningNå() { friFra = hode; spilles = nil }
                else if let k = valgt { spill(k) }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)

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
                            Button { spill(k) } label: { rad(k) }
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
                .onChange(of: øverst) { _, ny in
                    // Rulling VELGER den øverste raden og flytter tidslinja dit — uten
                    // animasjon og uten å røre spilleren. Ingen tunge utregninger her:
                    // alt dette kjører for hver rad som passerer.
                    guard !ruller, let id = ny, let k = hendelser.first(where: { $0.id == id }) else { return }
                    valgt = k
                    vindu = .init(midt: k.iv.start, spenn: vindu.spenn)
                    hode = k.iv.start
                    forhåndshent(rundt: id)
                }
                .refreshable { await last() }
                .onChange(of: valgt?.id) { _, ny in
                    // Rull til den valgte, ellers kan den blå rammen ligge utenfor skjermen.
                    // Bare når valget kom fra tidslinja — ikke når det kom fra rullingen selv.
                    guard let ny, øverst != ny else { return }
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
            } else if let k = spilles, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
                // IKKE tving 16:9 på hele feltet: kontrollbaren ligger inni Spiller, og da
                // måtte bildet krympe for å gi plass — resultatet var svarte kanter på
                // sidene. Spiller styrer selv bildets sideforhold.
                Spiller(url: url, markering: k.markering, lengde: k.iv.lengde)
                    .id(k.id)   // ny spiller per klipp — ellers henger forrige igjen
            } else {
                // Ingenting spiller ennå. Viser den valgte hendelsen som stillbilde med en
                // avspillingsknapp oppå — så er det tydelig at noe venter på et trykk,
                // framfor en evig ProgressView som ser ut som en feil.
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.black)
                    if let k = valgt {
                        EnkeltRamme(api: api, klipp: k).opacity(0.55)
                        Button { spill(k) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "play.circle.fill").font(.system(size: 46))
                                Text(k.iv.start, format: .dateTime.hour().minute().second())
                                    .font(.caption.monospacedDigit())
                            }
                            .foregroundStyle(.white.opacity(0.95))
                        }
                    } else {
                        Text(hendelser.isEmpty ? "Ingen opptak å vise" : "Velg en hendelse")
                            .font(.footnote).foregroundStyle(Farge.svak)
                    }
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            }
        }
        // Ingen sidemarg: bildet skal gå helt ut i kantene. Margen ga en svart ramme
        // rundt videoen som så ut som letterboxing.
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
        .overlay(alignment: .topLeading) { statusmerke }
        .animation(.easeOut(duration: 0.2), value: nedlaster.tilstand)
        .onChange(of: valgt?.id) { _, _ in nedlaster.nullstill(); låsefeil = nil }
        // Kvitteringen skal si fra og så forsvinne — ikke bli stående som noe man må
        // gjøre noe med.
        .onChange(of: nedlaster.tilstand) { _, ny in
            guard ny == .ferdig else { return }
            Task {
                try? await Task.sleep(for: .seconds(4))
                if nedlaster.tilstand == .ferdig { nedlaster.nullstill() }
            }
        }
        .overlay(alignment: .topTrailing) {
            if spilles != nil {
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
            } else if let k = spilles, let url = api.opptakURL(kamera: k.kamera, klipp: k.iv) {
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
        guard let n = spilles ?? valgt,
              let i = hendelser.firstIndex(where: { $0.id == n.id }) else { return }
        let mål = i + retning
        if hendelser.indices.contains(mål) { spill(hendelser[mål]) }
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
                    .background(fritt ? Farge.ok.opacity(0.22) : Farge.kort2)
                    .foregroundStyle(fritt ? Farge.ok : Farge.dempet)
                    .clipShape(Capsule())
            }
            Button("Nå") { gåTilNå() }
                .font(.caption).foregroundStyle(Farge.aksent)
        }
        .padding(.horizontal, 16).padding(.top, 8)
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
            // Låsemerket ligger PÅ stripa, i samme form som varigheten. Et lite ikon nede
            // i metadata-linja ble borte i mengden — og et låst klipp er nettopp det man
            // skal kunne se på et halvt blikk mens man blar.
            .overlay(alignment: .topTrailing) {
                if erLåst(k) {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                        Text("Låst").font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.75))
                    .foregroundStyle(Farge.aksent)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "figure.walk").font(.caption2).foregroundStyle(Farge.aksent)
                Text(k.iv.start, format: .dateTime.hour().minute().second())
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Farge.tekst)
                Spacer()
                if nåværende(k) {
                    Text("spilles").font(.caption2).foregroundStyle(Farge.aksent)
                } else if erValgt(k) {
                    Text("trykk for å spille").font(.caption2).foregroundStyle(Farge.kjol)
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(Farge.kort)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(nåværende(k) ? Farge.aksent : (erValgt(k) ? Farge.kjol : .clear),
                        lineWidth: 2)
        )
    }

    /// ORANSJE: spilles nå.  BLÅ: valgt, venter på et trykk.
    ///
    /// Begge er rene id-sammenligninger. Før lette den ene av dem gjennom hele
    /// hendelseslista for å finne nærmeste klipp — og den ble kalt for HVER synlige rad,
    /// altså O(n²) per rullebilde. Det var hovedgrunnen til hakkingen.
    private func nåværende(_ k: Klipp) -> Bool { spilles?.id == k.id }
    private func erValgt(_ k: Klipp) -> Bool { valgt?.id == k.id && spilles?.id != k.id }

    /// Velger uten å spille — flytter markøren og sentrerer tidslinja.
    private func velg(_ k: Klipp) {
        valgt = k
        hode = k.iv.start
        withAnimation(.easeOut(duration: 0.25)) {
            vindu = .init(midt: k.iv.start, spenn: vindu.spenn)
        }
    }

    /// Starter avspilling. Eneste vei inn i spilleren — ingenting starter av seg selv.
    private func spill(_ k: Klipp) {
        valgt = k
        spilles = k
        hode = k.iv.start
        withAnimation(.easeOut(duration: 0.25)) {
            vindu = .init(midt: k.iv.start, spenn: vindu.spenn)
        }
    }

    /// Om tidspunktet spillehodet står på har kontinuerlig dekning (til fri spoling).
    private func påDekningNå() -> Bool {
        guard let kam = kamera else { return false }
        let u = hode.timeIntervalSince1970
        return kam.kontinuerlig.contains { u >= $0.sUnix && u <= $0.eUnix }
    }

    private var erIdag: Bool {
        Calendar.current.isDate(dag, inSameDayAs: .now)
    }

    private func flyttDag(_ n: Int) {
        guard let ny = Calendar.current.date(byAdding: .day, value: n, to: dag) else { return }
        dag = ny
        valgt = nil; spilles = nil
        oppdaterHendelser()
        let midt = Calendar.current.isDate(ny, inSameDayAs: .now)
            ? Date.now
            : ny.addingTimeInterval(12 * 3600)
        vindu = .init(midt: midt, spenn: vindu.spenn)
        hode = midt
    }

    private func gåTilNå() {
        dag = Calendar.current.startOfDay(for: .now)
        oppdaterHendelser()
        vindu = .init(midt: .now, spenn: vindu.spenn)
        hode = .now
    }

    /// Henter miniatyrbilder et stykke UTENFOR det synlige, i begge retninger — da føles
    /// lista ferdig lastet uansett hvilken vei man ruller, uten å hente alle 250.
    private func forhåndshent(rundt id: Klipp.ID) {
        guard let i = hendelser.firstIndex(where: { $0.id == id }) else { return }
        let fra = max(0, i - 12), til = min(hendelser.count - 1, i + 20)
        guard fra <= til else { return }
        Bildelager.delt.forhåndshent(hendelser[fra...til].compactMap {
            api.stripeURL(kamera: $0.kamera, alarmUnix: ($0.alarm ?? $0.iv).sUnix)
        })
    }

    private func varighet(_ iv: Intervall) -> String {
        let d = Int(iv.lengde.rounded())
        return String(format: "%d:%02d", d / 60, d % 60)
    }

    /// Låste klipp for DETTE kameraet. Feiler kallet, viser vi bare ingen hengelåser —
    /// det er bedre enn å blokkere hele opptaksvisningen for en pynt-detalj.
    private func lastLåste() async {
        låste = ((try? await api.låsteKlipp()) ?? []).filter { $0.navn == kameranavn }
    }

    private func last() async {
        laster = kameraer.isEmpty
        defer { laster = false }
        await lastLåste()
        do {
            kameraer = try await api.tidslinje()
            feil = nil
            oppdaterHendelser()
            // Nyeste hendelse blir VALGT, ikke spilt. Appen skal ikke begynne å spille
            // av seg selv når man åpner den.
            if valgt == nil, let første = hendelser.first {
                velg(første)
                forhåndshent(rundt: første.id)
            }
        } catch {
            // Avbrutt forespørsel = fanebytte, ikke en feil verdt å vise.
            if !erAvbrutt(error) { feil = error.localizedDescription }
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
                    // ScrollView med kort, ikke List: velgeren skal se ut som den på Live.
                    // En List-rad kan ikke gi samme kortform med topplinje over bildet.
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(kameraer, id: \.navn) { kam in
                                NavigationLink(value: kam.navn) { rad(kam) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                    }
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

    /// Samme kortform som `LiveKort` på Live-fanen: topplinje med markør, navn og
    /// utvid-hint, og bildet i full bredde under. Thomas ville ha én velger-form begge
    /// steder, og likte live-varianten best.
    ///
    /// Forskjellen som må være der: dette er et STILLBILDE av nyeste hendelse — en
    /// opptaksvelger kan ikke spille live. Alt annet er likt.
    private func rad(_ kam: KameraTL) -> some View {
        let siste = kam.deteksjonsklipp.last
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "figure.walk")
                    .font(.caption2).foregroundStyle(Farge.aksent)
                Text(kam.navn).foregroundStyle(Farge.tekst).font(.subheadline.weight(.medium))
                Spacer()
                if let iv = siste {
                    HStack(spacing: 4) {
                        Text(iv.start, format: .dateTime.hour().minute())
                        Text("· \(kam.deteksjonsklipp.count)")
                    }
                    .font(.caption).foregroundStyle(Farge.dempet)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(Farge.dempet)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            if let iv = siste {
                EnkeltRamme(api: api, klipp: Klipp(kamera: kam.navn, iv: iv, alarm: kam.alarm(i: iv)))
            } else {
                Rectangle().fill(Farge.kort2).aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay(Text("ingen klipp").font(.caption).foregroundStyle(Farge.svak))
            }
        }
        .kort()
    }

    private func last() async {
        do { kameraer = try await api.tidslinje(); feil = nil }
        catch { if !erAvbrutt(error) { feil = error.localizedDescription } }
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
        Mellomlagret(url: api.stripeURL(kamera: klipp.kamera,
                                        alarmUnix: (klipp.alarm ?? klipp.iv).sUnix))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Viser ÉN ramme av film-stripa, i full bredde. Stripa er fire rammer ved siden av
/// hverandre; vi skalerer den fire ganger og klipper ut én.
///
/// **Ikke den første.** Klippet begynner 10 sekunder FØR bevegelsen (`alarm_pre` på
/// kameraet), så ramme 1 er med vilje tatt før noe skjer: tom oppkjørsel om dagen, helt
/// svart om natta før lyset slår på. Ramme 3 ligger midt i hendelsen, og er den som viser
/// hva som faktisk skjedde. Hendelseslista viser hele stripa og merket derfor ingenting —
/// det var bare kameravelgeren som så tom ut.
struct EnkeltRamme: View {
    let api: API
    let klipp: Klipp
    /// 0–3. Standard er tredje ramme; se forklaringen over.
    var ramme: Int = 2

    var body: some View {
        GeometryReader { geo in
            let b = geo.size.width
            Mellomlagret(url: api.stripeURL(kamera: klipp.kamera,
                                            alarmUnix: (klipp.alarm ?? klipp.iv).sUnix), fyll: true)
                .frame(width: b * 4, height: geo.size.height, alignment: .leading)
                .offset(x: -b * CGFloat(min(max(ramme, 0), 3)))
                .frame(width: b, height: geo.size.height, alignment: .leading)
                .clipped()
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
}
