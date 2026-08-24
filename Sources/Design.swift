import SwiftUI

/// Fargene fra smarthus-dashbordet (`app/src/index.css`). Appen skal føles som samme
/// system — ikke et fremmed produkt som tilfeldigvis viser de samme kameraene.
enum Farge {
    static let flate  = Color(hex: 0x0B0D10)  // nesten svart, ikke ren svart
    static let kort   = Color(hex: 0x14171C)
    static let kort2  = Color(hex: 0x1B1F26)
    static let strek  = Color(hex: 0x232830)  // linjer og skiller — aldri tekst
    static let svak   = Color(hex: 0x5B6270)  // svakeste LESBARE tekst
    static let dempet = Color(hex: 0x8A919C)  // etiketter
    static let tekst  = Color(hex: 0xE8EAED)
    static let aksent = Color(hex: 0xF5A524)  // varm gul: interaktivt og aktivt
    static let ok     = Color(hex: 0x4ADE80)
    static let avvik  = Color(hex: 0xF87171)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255)
    }
}

/// Kortflaten dashbordet bruker overalt: dempet flate, myk radius, tynn kant.
struct Kort: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Farge.kort)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Farge.strek, lineWidth: 1))
    }
}

extension View {
    func kort() -> some View { modifier(Kort()) }
}
