#!/usr/bin/env swift
// Baut den GitHub-Social-Banner / README-Hero (1280x640): Icon links,
// Titel/Untertitel/Tagline rechts. Bewusst sehr aehnlich zur Mac-App
// „Mucke, Baby!" gehalten. Nativ via AppKit/CoreGraphics, keine Abhaengigkeiten.
//
// Aufruf:
//   swift make-banner.swift [ICON_PNG] [OUT_PNG]
// Defaults: brushed s123 -> social-baby-mucke.png
import AppKit

let args = CommandLine.arguments
let iconPath = args.count > 1 ? args[1] : "app-icon-brushed-s123.png"
let outPath  = args.count > 2 ? args[2] : "social-baby-mucke.png"

let W = 1280.0, H = 640.0
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// --- Hintergrund: diagonaler dunkler Verlauf (oben-links heller -> unten-rechts fast schwarz)
let bg = NSGradient(colors: [
    NSColor(srgbRed: 0.13, green: 0.14, blue: 0.18, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1),
])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -55)

// --- Icon links, vertikal zentriert
let iconSize = 280.0
let iconX = 70.0
let iconY = (H - iconSize) / 2
if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
}

// --- Textblock rechts
let textX = iconX + iconSize + 70.0   // = 420

func draw(_ s: String, font: NSFont, color: NSColor, topY: CGFloat) {
    // topY = Abstand der Textoberkante von der OBERKANTE des Banners.
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    let lineH = font.ascender - font.descender
    // AppKit-Origin ist unten-links -> Baseline-Punkt von oben her umrechnen.
    let y = H - topY - lineH
    str.draw(at: NSPoint(x: textX, y: y))
}

// Titel separat mit etwas Kerning nach dem Komma — sonst klebt ", M" zusammen.
let titleStr = "Baby, Mucke!"
let titleFont = NSFont.systemFont(ofSize: 82, weight: .bold)
let title = NSMutableAttributedString(
    string: titleStr,
    attributes: [.font: titleFont, .foregroundColor: NSColor.white])
if let r = titleStr.range(of: ",") {
    title.addAttribute(.kern, value: 12.0, range: NSRange(r, in: titleStr))
}
let titleLineH = titleFont.ascender - titleFont.descender
title.draw(at: NSPoint(x: textX, y: H - 180 - titleLineH))
draw("Webradio-Player für iPhone",
     font: .systemFont(ofSize: 36, weight: .regular),
     color: NSColor(srgbRed: 0.80, green: 0.82, blue: 0.86, alpha: 1),
     topY: 300)
draw("Songtitel · Verlauf · Titelsuche bei Apple Music & Spotify",
     font: .systemFont(ofSize: 26, weight: .medium),
     color: NSColor(srgbRed: 0.21, green: 0.90, blue: 1.0, alpha: 1),  // Black-MIDI-Cyan
     topY: 376)

image.unlockFocus()

// --- als PNG schreiben
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG-Erzeugung fehlgeschlagen\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("geschrieben: \(outPath)")
