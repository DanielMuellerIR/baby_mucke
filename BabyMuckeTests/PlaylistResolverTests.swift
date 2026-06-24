import XCTest
@testable import BabyMucke

// Testet die reinen Parse-/Heuristik-Anteile des Playlist-Resolvers
// (needsResolution, firstMediaURL, firstMatch). Die netzgebundenen Teile
// (resolve, fetchHead) werden hier bewusst nicht angefasst.
final class PlaylistResolverTests: XCTestCase {

    // MARK: - needsResolution

    func testNeedsResolutionForPlaylistContainers() {
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://x/y.pls")!))
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://x/list.m3u")!))
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://x/list.asx")!))
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://x/list.xspf")!))
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://opml.radiotime.com/Tune.ashx?id=1")!))
    }

    // Regressions-Guard: TuneIn-Endpunkt mit Endung "-pls" (gebuendelter
    // Sender HardBase.FM) muss als aufzuloesende Playlist erkannt werden.
    func testNeedsResolutionForDashPlsEndpoint() {
        XCTAssertTrue(PlaylistResolver.needsResolution(URL(string: "http://listen.hardbase.fm/tunein-aac-hd-pls")!))
    }

    func testNoResolutionForDirectStreamsAndHLS() {
        XCTAssertFalse(PlaylistResolver.needsResolution(URL(string: "https://x/stream.mp3")!))
        XCTAssertFalse(PlaylistResolver.needsResolution(URL(string: "https://x/stream.aac")!))
        // .m3u8 ist HLS und wird absichtlich NICHT als Playlist-Container behandelt.
        XCTAssertFalse(PlaylistResolver.needsResolution(URL(string: "https://x/master.m3u8")!))
        // "-pls" mitten im Host (nicht an einer Pfad-Grenze) ist KEINE Playlist.
        XCTAssertFalse(PlaylistResolver.needsResolution(URL(string: "https://my-pls-cdn.example/stream.mp3")!))
    }

    // MARK: - firstMediaURL

    func testFirstMediaURLFromPLS() {
        let body = "[playlist]\nNumberOfEntries=1\nFile1=http://stream.example/aac\nTitle1=Test\n"
        XCTAssertEqual(PlaylistResolver.firstMediaURL(in: body)?.absoluteString, "http://stream.example/aac")
    }

    func testFirstMediaURLFromM3U() {
        let body = "#EXTM3U\n#EXTINF:-1,Test\nhttp://stream.example/mp3\n"
        XCTAssertEqual(PlaylistResolver.firstMediaURL(in: body)?.absoluteString, "http://stream.example/mp3")
    }

    func testFirstMediaURLFromASXDoubleQuote() {
        let body = "<asx version=\"3.0\"><entry><ref href=\"http://a.example/stream\"/></entry></asx>"
        XCTAssertEqual(PlaylistResolver.firstMediaURL(in: body)?.absoluteString, "http://a.example/stream")
    }

    // Regressions-Guard: ASX mit href in EINFACHEN Anfuehrungszeichen.
    func testFirstMediaURLFromASXSingleQuote() {
        let body = "<asx version='3.0'><entry><ref href='http://b.example/stream'/></entry></asx>"
        XCTAssertEqual(PlaylistResolver.firstMediaURL(in: body)?.absoluteString, "http://b.example/stream")
    }

    func testFirstMediaURLFromXSPFLocation() {
        let body = "<playlist><trackList><track><location>http://c.example/stream</location></track></trackList></playlist>"
        XCTAssertEqual(PlaylistResolver.firstMediaURL(in: body)?.absoluteString, "http://c.example/stream")
    }

    func testFirstMediaURLNilForNoURL() {
        XCTAssertNil(PlaylistResolver.firstMediaURL(in: "kein link hier\nnur text"))
    }

    // MARK: - firstMatch

    func testFirstMatchReturnsCapturedGroup() {
        let m = PlaylistResolver.firstMatch("<location>http://d.example/s</location>",
                                            pattern: "<location>\\s*(https?://[^<\\s]+)")
        XCTAssertEqual(m, "http://d.example/s")
    }
}
