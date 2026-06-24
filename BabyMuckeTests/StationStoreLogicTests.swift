import XCTest
@testable import BabyMucke

// Testet die Lade-/Seed-/Migrations- und Import-Normalisierung des StationStore
// ueber die oeffentliche API mit injiziertem Temp-Ordner. StationStore ist
// @MainActor, daher die Klasse ebenfalls.
@MainActor
final class StationStoreLogicTests: XCTestCase {

    private func tempBase() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-store-\(UUID().uuidString)", isDirectory: true)
    }

    // Schreibt eine stations.json in den Unterordner, den StationStore.init erwartet.
    private func writeStations(_ json: String, into base: URL) throws {
        let dir = base.appendingPathComponent("BabyMucke", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("stations.json"))
    }

    // MARK: - Laden / Seed / Migration

    func testFreshDirSeedsNonEmpty() {
        // Ohne vorhandene Liste werden die gebuendelten Seeds geladen.
        let store = StationStore(directory: tempBase())
        XCTAssertFalse(store.stations.isEmpty)
    }

    func testEditedListIsPreserved() throws {
        let base = tempBase()
        try writeStations(#"[{"name":"Eins","url":"http://a"},{"name":"Zwei","url":"http://b"}]"#, into: base)
        let store = StationStore(directory: base)
        // Eine bearbeitete (nicht-Demo-)Liste bleibt unveraendert.
        XCTAssertEqual(store.stations.map(\.name), ["Eins", "Zwei"])
    }

    func testLegacyDemoListIsMigrated() throws {
        let base = tempBase()
        let demo = StationStore.builtinDefaults.map { $0.toStation() }
        let json = String(decoding: try JSONEncoder().encode(demo), as: UTF8.self)
        try writeStations(json, into: base)
        let store = StationStore(directory: base)
        // Die unberuehrte 4-Sender-Demoliste wird durch die gebuendelten Seeds ersetzt.
        XCTAssertNotEqual(store.stations.map(\.name), StationStore.builtinDefaults.map(\.name))
    }

    // MARK: - Import / Normalisierung

    func testImportReplacesStations() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let file = base.appendingPathComponent("import.json")
        try Data(#"[{"name":"Imported","url":"http://x"}]"#.utf8).write(to: file)
        try store.importStations(fromFile: file)
        XCTAssertEqual(store.stations.map(\.name), ["Imported"])
    }

    func testImportDeduplicatesDuplicateIDs() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let id = UUID().uuidString
        let json = #"[{"id":"\#(id)","name":"A","url":"http://a"},{"id":"\#(id)","name":"B","url":"http://b"}]"#
        let file = base.appendingPathComponent("dup.json")
        try Data(json.utf8).write(to: file)
        try store.importStations(fromFile: file)
        XCTAssertEqual(store.stations.count, 2)
        XCTAssertNotEqual(store.stations[0].id, store.stations[1].id)
    }

    func testImportTrimsAndDropsInvalid() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let json = #"[{"name":"  Sauber  ","url":"  http://x  "},{"name":"","url":"http://y"}]"#
        let file = base.appendingPathComponent("mix.json")
        try Data(json.utf8).write(to: file)
        try store.importStations(fromFile: file)
        XCTAssertEqual(store.stations.count, 1)
        XCTAssertEqual(store.stations[0].name, "Sauber")
        XCTAssertEqual(store.stations[0].url, "http://x")
    }

    func testImportThrowsWhenAllInvalid() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let file = base.appendingPathComponent("empty.json")
        try Data(#"[{"name":"","url":""}]"#.utf8).write(to: file)
        XCTAssertThrowsError(try store.importStations(fromFile: file))
    }
}
