import XCTest
@testable import BabyMucke

// Testet die Lade-/Seed-/Migrations- und Import-Normalisierung des StationStore
// ueber die oeffentliche API mit injiziertem Temp-Ordner. StationStore ist
// @MainActor, daher die Klasse ebenfalls.
@MainActor
final class StationStoreLogicTests: XCTestCase {

    private final class PlayerFake: StationListPlayback {
        var currentStation: Station?
        var selectedStations: [Station] = []
        var refreshedStations: [Station] = []
        var stopAndClearCount = 0

        func select(_ station: Station) {
            selectedStations.append(station)
            currentStation = station
        }

        func refreshCurrentStation(_ station: Station) {
            refreshedStations.append(station)
            currentStation = station
        }

        func stopAndClearSelection() {
            stopAndClearCount += 1
            currentStation = nil
        }
    }

    private var tempDirs: [URL] = []

    override func tearDown() {
        super.tearDown()
        for url in tempDirs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirs.removeAll()
    }

    private func tempBase() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-store-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        return dir
    }

    // Schreibt eine stations.json in den Unterordner, den StationStore.init erwartet.
    private func writeStations(_ json: String, into base: URL) throws {
        let dir = base.appendingPathComponent("BabyMucke", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("stations.json"))
    }

    private func importStations(_ stations: [Station], into store: StationStore,
                                from base: URL) throws {
        let file = base.appendingPathComponent("import-sync.json")
        try JSONEncoder().encode(stations).write(to: file)
        try store.importStations(fromFile: file)
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

    // MARK: - Wiedergabe-Auswahl

    func testDefaultStationSkipsDisabledFavorite() {
        let suiteName = "BabyMuckeTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = StationStore(directory: tempBase(), defaults: defaults)
        let disabledFavorite = Station(
            name: "Aus", url: "http://invalid/disabled", enabled: false, favorite: true
        )
        let enabled = Station(name: "An", url: "http://invalid/enabled")
        store.stations = [disabledFavorite, enabled]
        store.markPlayed(disabledFavorite)

        XCTAssertEqual(store.defaultStation?.id, enabled.id)
    }

    func testDeleteCurrentStopsAndClearsWithoutActiveFallback() {
        let store = StationStore(directory: tempBase())
        let deleted = Station(name: "Gelöscht", url: "http://invalid/deleted")
        store.stations = [deleted]
        let player = PlayerFake()
        player.currentStation = deleted

        store.delete(deleted)
        StationListSynchronizer.synchronize(store: store, player: player)

        XCTAssertEqual(player.stopAndClearCount, 1)
        XCTAssertNil(player.currentStation)
        XCTAssertTrue(player.selectedStations.isEmpty)
    }

    func testImportReplacesOrphanWithEnabledDefault() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let old = Station(name: "Alt", url: "http://invalid/old")
        store.stations = [old]
        let disabledFavorite = Station(
            name: "Aus", url: "http://invalid/disabled", enabled: false, favorite: true
        )
        let enabled = Station(name: "An", url: "http://invalid/enabled")
        let player = PlayerFake()
        player.currentStation = old

        try importStations([disabledFavorite, enabled], into: store, from: base)
        StationListSynchronizer.synchronize(store: store, player: player)

        XCTAssertEqual(player.stopAndClearCount, 1)
        XCTAssertEqual(player.currentStation?.id, enabled.id)
        XCTAssertEqual(player.selectedStations.map(\.id), [enabled.id])
    }

    func testImportWithOnlyDisabledStationsStopsAndClearsOrphan() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let old = Station(name: "Alt", url: "http://invalid/old")
        store.stations = [old]
        let player = PlayerFake()
        player.currentStation = old
        let disabled = Station(
            name: "Aus", url: "http://invalid/disabled", enabled: false, favorite: true
        )

        try importStations([disabled], into: store, from: base)
        StationListSynchronizer.synchronize(store: store, player: player)

        XCTAssertEqual(player.stopAndClearCount, 1)
        XCTAssertNil(player.currentStation)
        XCTAssertTrue(player.selectedStations.isEmpty)
    }

    func testImportRefreshesStillEnabledCurrentStation() throws {
        let base = tempBase()
        let store = StationStore(directory: base)
        let id = UUID()
        let old = Station(id: id, name: "Alt", url: "http://invalid/old")
        let imported = Station(id: id, name: "Neu", url: "http://invalid/new")
        store.stations = [old]
        let player = PlayerFake()
        player.currentStation = old

        try importStations([imported], into: store, from: base)
        StationListSynchronizer.synchronize(store: store, player: player)

        XCTAssertEqual(player.stopAndClearCount, 0)
        XCTAssertTrue(player.selectedStations.isEmpty)
        XCTAssertEqual(player.refreshedStations, [imported])
        XCTAssertEqual(player.currentStation, imported)
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
