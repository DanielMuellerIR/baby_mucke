import XCTest
@testable import BabyMucke

// Testet die Aufteilung eines ICY-Rohtitels in Interpret und Titel.
// SongEntry.split ist reine, deterministische Logik (kein Netz, keine Platte),
// also gut headless pruefbar.
final class SongEntrySplitTests: XCTestCase {

    func testArtistAndTitle() {
        let r = SongEntry.split("Daft Punk - Get Lucky")
        XCTAssertEqual(r.artist, "Daft Punk")
        XCTAssertEqual(r.title, "Get Lucky")
    }

    func testTitleOnlyWhenNoSeparator() {
        let r = SongEntry.split("Untitled Track")
        XCTAssertNil(r.artist)
        XCTAssertEqual(r.title, "Untitled Track")
    }

    func testTrimsSurroundingWhitespace() {
        let r = SongEntry.split("   A   -   B   ")
        // Es wird am " - " getrennt und jede Haelfte einzeln getrimmt.
        XCTAssertEqual(r.artist, "A")
        XCTAssertEqual(r.title, "B")
    }

    func testSplitsOnlyOnFirstSeparator() {
        // Nur die ERSTE " - "-Stelle trennt; der Rest bleibt im Titel.
        let r = SongEntry.split("A - B - C")
        XCTAssertEqual(r.artist, "A")
        XCTAssertEqual(r.title, "B - C")
    }

    func testEmptyStringYieldsNilNil() {
        let r = SongEntry.split("   ")
        XCTAssertNil(r.artist)
        XCTAssertNil(r.title)
    }
}
