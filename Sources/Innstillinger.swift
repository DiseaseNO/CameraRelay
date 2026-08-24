import SwiftUI

struct Innstillinger: View {
    let api: API
    @State private var bekreft = false

    var body: some View {
        NavigationStack {
            ZStack {
                Farge.flate.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server").font(.footnote).foregroundStyle(Farge.dempet)
                        Text(api.vert ?? "—").foregroundStyle(Farge.tekst)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).kort()

                    Text("Enhets-tokenet ligger i Keychain og kan trekkes tilbake fra dashbordet under Admin → Enheter.")
                        .font(.caption).foregroundStyle(Farge.svak)

                    Button(role: .destructive) { bekreft = true } label: {
                        Text("Glem denne enheten")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Farge.kort2).foregroundStyle(Farge.avvik)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Innstillinger")
            .toolbarBackground(Farge.flate, for: .navigationBar)
            .confirmationDialog("Glemme enheten?", isPresented: $bekreft, titleVisibility: .visible) {
                Button("Glem", role: .destructive) { api.glemEnhet() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text("Du må pare på nytt med en ny kode fra dashbordet.")
            }
        }
    }
}
