import SwiftUI

// Feste Black-MIDI-Palette. Die App hat bewusst kein Theme-System: Schwarz als
// Grund, dazu Cyan, Pink, Gruen und Amber fuer klare Zustandsfarben.
enum BlackMidiStyle {
    static let background = Color(hex: "#05060A")
    static let panelFill = Color(hex: "#05060A").opacity(0.62)
    static let surface = Color(hex: "#10131C")
    static let surfaceRaised = Color(hex: "#161A26")
    static let line = Color(hex: "#2D3347")
    static let text = Color(hex: "#F3F7FF")
    static let secondaryText = Color(hex: "#9AA6BF")
    static let dimText = Color(hex: "#66708A")
    static let cyan = Color(hex: "#36E6FF")
    static let pink = Color(hex: "#FF4FD8")
    static let green = Color(hex: "#8DFF5A")
    static let amber = Color(hex: "#FFD166")
    static let red = Color(hex: "#FF5A6A")
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
    var body: some View {
        // Die Cyber-Textur (1280x800, Querformat) hat ihre hellen Details im oberen
        // Drittel. Im Hochformat zeigte ein einfaches scaledToFill darum nur oben
        // Struktur und unten Schwarz ("nur oben"). Loesung: die Textur gespiegelt
        // stapeln — obere Haelfte normal, untere Haelfte vertikal gespiegelt. So
        // rahmt die helle Struktur den Inhalt oben UND unten ("rundum"), die ruhige
        // dunkle Mitte haelt die Listentexte gut lesbar.
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
        .background(BlackMidiStyle.background)
        .overlay {
            BlackMidiStyle.background.opacity(0.28)   // dezenter Scrim, Textur bleibt sichtbar
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
