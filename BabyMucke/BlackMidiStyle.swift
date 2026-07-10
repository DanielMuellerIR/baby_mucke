import SwiftUI
import UIKit

// Gemeinsame Black-MIDI-Palette fuer beide Darstellungen. Die dynamischen Farben
// reagieren auf den von der App gesetzten ColorScheme; dadurch verwenden auch
// Sheets und Systemdialoge dieselbe manuell gewaehlte oder automatische Optik.
enum BlackMidiStyle {
    static let background = adaptive(dark: "#05060A", light: "#F7F4EC")
    // Leicht durchscheinender Panel-Grund: derselbe Hex-Wert wie `background`,
    // nur mit Deckkraft — nicht als zweites Literal pflegen.
    static let panelFill = background.opacity(0.76)
    static let surface = adaptive(dark: "#10131C", light: "#EEEAE0")
    static let surfaceRaised = adaptive(dark: "#161A26", light: "#FFFFFF")
    static let line = adaptive(dark: "#2D3347", light: "#C8C3B8")
    static let text = adaptive(dark: "#F3F7FF", light: "#151822")
    static let secondaryText = adaptive(dark: "#9AA6BF", light: "#596274")
    static let dimText = adaptive(dark: "#66708A", light: "#8D94A1")
    static let cyan = adaptive(dark: "#36E6FF", light: "#007B8F")
    static let pink = adaptive(dark: "#FF4FD8", light: "#A61E72")
    static let green = adaptive(dark: "#8DFF5A", light: "#287A22")
    static let amber = adaptive(dark: "#FFD166", light: "#986100")
    static let red = adaptive(dark: "#FF5A6A", light: "#BA2737")

    private static func adaptive(dark: String, light: String) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

struct PlaybackButtonStyle: ButtonStyle {
    var tint: Color = BlackMidiStyle.cyan
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(active ? tint.opacity(0.16) : BlackMidiStyle.surfaceRaised.opacity(0.68))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tint.opacity(configuration.isPressed ? 0.85 : 0.42), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct CompactIconButtonStyle: ButtonStyle {
    var tint: Color = BlackMidiStyle.cyan
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(filled ? BlackMidiStyle.background : tint)
            .frame(width: 30, height: 30)
            .background(filled ? tint : BlackMidiStyle.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(tint.opacity(configuration.isPressed ? 0.95 : 0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct BlackMidiBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Die Cyber-Textur (1280x800, Querformat) hat ihre hellen Details im oberen
        // Drittel. Im Hochformat zeigte ein einfaches scaledToFill darum nur oben
        // Struktur und unten Schwarz ("nur oben"). Loesung: die Textur gespiegelt
        // stapeln — obere Haelfte normal, untere Haelfte vertikal gespiegelt. So
        // rahmt die helle Struktur den Inhalt oben UND unten ("rundum"), die ruhige
        // dunkle Mitte haelt die Listentexte gut lesbar.
        ZStack {
            BlackMidiStyle.background

            GeometryReader { geo in
                VStack(spacing: 0) {
                    texture
                        .frame(width: geo.size.width, height: geo.size.height / 2)
                        .clipped()
                    texture
                        .frame(width: geo.size.width, height: geo.size.height / 2)
                        .clipped()
                        .scaleEffect(y: -1)   // untere Haelfte vertikal spiegeln
                }
            }

            if colorScheme == .dark {
                BlackMidiStyle.background.opacity(0.28)
            } else {
                // Im Light Mode wird dieselbe Textur zur feinen grauen Papier-
                // struktur. Eine hohe Deckkraft wuerde die Lesbarkeit mindern.
                BlackMidiStyle.background.opacity(0.84)
                    .blendMode(.screen)
            }
        }
        .clipped()
    }

    private var texture: some View {
        Image("BlackMidiBackground")
            .resizable()
            .scaledToFill()
    }
}

struct MIDIChip: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.55), lineWidth: 1)
            )
    }
}
