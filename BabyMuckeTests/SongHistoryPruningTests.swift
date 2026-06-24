import XCTest
@testable import BabyMucke

// Testet die Verlaufs-Pruning-Logik (note/closeCurrent/remove/clear) mit
// kontrollierten Zeitstempeln. Jeder Test bekommt einen eigenen Temp-Ordner
// injiziert, damit kein gemeinsamer verlauf.json-Zustand die Tests koppelt.
// SongHistory ist @MainActor, daher die Klasse ebenfalls.
@MainActor
final class SongHistoryPruningTests: XCTestCase {

    // Fester Zeitanker, damit die Dauer-Schwellen deterministisch sind.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func freshHistory() -> SongHistory {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-test-\(UUID().uuidString)", isDirectory: true)
        return SongHistory(directory: dir)
    }

    func testNoteAddsOpenEntryAndSplits() {
        let h = freshHistory()
        h.note(station: "S", raw: "Daft Punk - Get Lucky", at: t0)
        XCTAssertEqual(h.entries.count, 1)
        XCTAssertEqual(h.entries[0].raw, "Daft Punk - Get Lucky")
        XCTAssertEqual(h.entries[0].artist, "Daft Punk")
        XCTAssertEqual(h.entries[0].title, "Get Lucky")
        XCTAssertNil(h.entries[0].end)   // laeuft noch
    }

    func testNoteIgnoresEmptyRaw() {
        let h = freshHistory()
        h.note(station: "S", raw: "   ", at: t0)
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testNoteDedupesConsecutiveSameTitle() {
        let h = freshHistory()
        h.note(station: "S", raw: "Same Song", at: t0)
        h.note(station: "S", raw: "Same Song", at: t0.addingTimeInterval(3))
        // Gleicher offener Titel desselben Senders -> kein zweiter Eintrag.
        XCTAssertEqual(h.entries.count, 1)
    }

    func testShortFragmentRemovedWhenNextSongStarts() {
        let h = freshHistory()
        h.note(station: "S", raw: "Kurz", at: t0)
        // Naechster Titel nach nur 2 s -> "Kurz" (< 5 s) wird beim Schliessen entfernt.
        h.note(station: "S", raw: "Lang", at: t0.addingTimeInterval(2))
        XCTAssertEqual(h.entries.map(\.raw), ["Lang"])
    }

    func testLongEntryIsKept() {
        let h = freshHistory()
        h.note(station: "S", raw: "Erster", at: t0)
        // 10 s spaeter naechster Titel -> "Erster" (>= 5 s) bleibt erhalten.
        h.note(station: "S", raw: "Zweiter", at: t0.addingTimeInterval(10))
        XCTAssertEqual(h.entries.map(\.raw), ["Erster", "Zweiter"])
        XCTAssertEqual(h.entries[0].end, t0.addingTimeInterval(10))
    }

    func testRemoveOlderThanCutoff() {
        let h = freshHistory()
        h.note(station: "S", raw: "Alt", at: t0)
        h.note(station: "S", raw: "Neu", at: t0.addingTimeInterval(10))   // schliesst "Alt" bei +10
        h.closeCurrent(at: t0.addingTimeInterval(20))                      // schliesst "Neu" bei +20
        XCTAssertEqual(h.entries.count, 2)

        h.remove(olderThan: t0.addingTimeInterval(15))
        // "Alt" endete bei +10 (< +15) -> weg; "Neu" endete bei +20 -> bleibt.
        XCTAssertEqual(h.entries.map(\.raw), ["Neu"])
    }

    func testClearEmptiesHistory() {
        let h = freshHistory()
        h.note(station: "S", raw: "Irgendwas", at: t0)
        h.clear()
        XCTAssertTrue(h.entries.isEmpty)
    }
}
