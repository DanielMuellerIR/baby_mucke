import XCTest
@testable import BabyMucke

// Testet die toleranten Codable-Decoder von Station und SeedStation.
// Handgepflegte JSON-Dateien duerfen Felder weglassen, ohne dass die ganze
// Liste unbrauchbar wird — genau das wird hier abgesichert.
final class StationDecodingTests: XCTestCase {

    private func decodeStations(_ json: String) throws -> [Station] {
        try JSONDecoder().decode([Station].self, from: Data(json.utf8))
    }

    func testStationFillsDefaultsForMissingFields() throws {
        let list = try decodeStations(#"[{"name":"WDR 5","url":"http://example/stream"}]"#)
        XCTAssertEqual(list.count, 1)
        let s = list[0]
        XCTAssertEqual(s.name, "WDR 5")
        XCTAssertEqual(s.url, "http://example/stream")
        XCTAssertTrue(s.enabled)        // Default true
        XCTAssertFalse(s.favorite)      // Default false
    }

    func testStationPreservesExplicitFields() throws {
        let uuid = UUID()
        let json = #"[{"id":"\#(uuid.uuidString)","name":"X","url":"u","enabled":false,"favorite":true}]"#
        let s = try decodeStations(json)[0]
        XCTAssertEqual(s.id, uuid)
        XCTAssertFalse(s.enabled)
        XCTAssertTrue(s.favorite)
    }

    func testStationDecodeFailsWithoutName() {
        // name und url sind Pflicht; fehlt name, muss das Dekodieren werfen.
        XCTAssertThrowsError(try decodeStations(#"[{"url":"u"}]"#))
    }

    func testStationGetsFreshIDWhenMissing() throws {
        // Ohne id wird eine frische UUID vergeben (also nicht die Null-UUID).
        let s = try decodeStations(#"[{"name":"X","url":"u"}]"#)[0]
        XCTAssertNotEqual(s.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    func testSeedStationDefaultsAndToStation() throws {
        let seeds = try JSONDecoder().decode([SeedStation].self,
                                              from: Data(#"[{"name":"Seed","url":"http://seed/stream"}]"#.utf8))
        XCTAssertEqual(seeds.count, 1)
        XCTAssertTrue(seeds[0].enabled)
        XCTAssertFalse(seeds[0].favorite)

        let station = seeds[0].toStation()
        XCTAssertEqual(station.name, "Seed")
        XCTAssertEqual(station.url, "http://seed/stream")
        XCTAssertTrue(station.enabled)
    }
}
