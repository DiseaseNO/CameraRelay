import SwiftUI
import UIKit

/// Førstegangsoppsett. Passordet ditt skal aldri inn i appen: du henter en engangskode
/// i smarthus-dashbordet (Admin → Enheter), og den veksles inn i et enhets-token her.
struct Paring: View {
    let api: API
    @State private var vert = ""
    @State private var kode = ""
    @State private var holderPå = false
    @State private var feil: String?

    var body: some View {
        ZStack {
            Farge.flate.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CameraRelay").font(.largeTitle.weight(.semibold)).foregroundStyle(Farge.tekst)
                    Text("Koble til smarthuset").foregroundStyle(Farge.dempet)
                }

                felt("Server", tekst: $vert, plassholder: "frcr.gustavs1.no",
                     hjelp: "Adressen til backend. Ingen «https://» foran.")
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                felt("Paringskode", tekst: $kode, plassholder: "123456",
                     hjelp: "Hentes i dashbordet under Admin → Enheter. Gyldig i 5 minutter.")
                    .keyboardType(.numberPad)

                if let feil {
                    Label(feil, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Farge.avvik)
                }

                Button {
                    Task { await par() }
                } label: {
                    HStack {
                        if holderPå { ProgressView().tint(Farge.flate) }
                        Text(holderPå ? "Kobler til …" : "Koble til")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(kanSende ? Farge.aksent : Farge.strek)
                    .foregroundStyle(kanSende ? Farge.flate : Farge.svak)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!kanSende)

                Spacer()
            }
            .padding(24)
        }
    }

    private var kanSende: Bool { !vert.isEmpty && kode.count == 6 && !holderPå }

    private func felt(_ tittel: String, tekst: Binding<String>, plassholder: String, hjelp: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tittel).font(.footnote).foregroundStyle(Farge.dempet)
            TextField(plassholder, text: tekst)
                .autocorrectionDisabled()
                .padding(12).background(Farge.kort2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(Farge.tekst)
            Text(hjelp).font(.caption2).foregroundStyle(Farge.svak)
        }
    }

    private func par() async {
        holderPå = true; feil = nil
        defer { holderPå = false }
        do {
            // UIDevice.current er main-actor-isolert; les navnet der før vi går async.
            let enhetsnavn = await MainActor.run { UIDevice.current.name }
            try await api.par(vert: vert, kode: kode, enhetsnavn: enhetsnavn)
        } catch {
            feil = error.localizedDescription
        }
    }
}
