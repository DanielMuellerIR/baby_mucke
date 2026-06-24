import XCTest
import SwiftUI
import UIKit
@testable import BabyMucke

// Testet den Hex-String-Initializer von Color (BlackMidiStyle.swift).
// Zum Pruefen der Komponenten wird die Color ueber UIColor in RGBA zerlegt.
final class ColorHexTests: XCTestCase {

    private func rgb(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    func testParsesRedWithHash() {
        let c = rgb(Color(hex: "#FF0000"))
        XCTAssertEqual(c.r, 1, accuracy: 0.02)
        XCTAssertEqual(c.g, 0, accuracy: 0.02)
        XCTAssertEqual(c.b, 0, accuracy: 0.02)
    }

    func testParsesGreenWithoutHash() {
        let c = rgb(Color(hex: "00FF00"))
        XCTAssertEqual(c.r, 0, accuracy: 0.02)
        XCTAssertEqual(c.g, 1, accuracy: 0.02)
        XCTAssertEqual(c.b, 0, accuracy: 0.02)
    }

    func testParsesBlue() {
        let c = rgb(Color(hex: "#0000FF"))
        XCTAssertEqual(c.b, 1, accuracy: 0.02)
    }

    func testMalformedHexFallsBackToBlack() {
        // Scanner findet keine Hex-Ziffern -> v bleibt 0 -> Schwarz, kein Absturz.
        let c = rgb(Color(hex: "nope"))
        XCTAssertEqual(c.r, 0, accuracy: 0.02)
        XCTAssertEqual(c.g, 0, accuracy: 0.02)
        XCTAssertEqual(c.b, 0, accuracy: 0.02)
    }
}
