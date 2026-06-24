import XCTest
@testable import BabyMucke

// Testet den Bau der Such-URLs fuer Apple Music und Spotify sowie die
// Titel-Bereinigung. Alles reine Funktionen ohne Netz.
final class MusicLinksTests: XCTestCase {

    // Kleiner Helfer, um einen Verlaufseintrag fuer die Tests zu bauen.
    private func entry(artist: String?, title: String?, raw: String) -> SongEntry {
        SongEntry(station: "Teststation", raw: raw, artist: artist, title: title, start: Date())
    }

    // MARK: - query

    func testQueryUsesArtistAndCleanedTitle() {
        let e = entry(artist: "Daft Punk", title: "Get Lucky", raw: "Daft Punk - Get Lucky")
        XCTAssertEqual(MusicLinks.query(for: e), "Daft Punk Get Lucky")
    }

    func testQueryFallsBackToRawWhenNoSplit() {
        let e = entry(artist: nil, title: nil, raw: "Nur ein Titel")
        XCTAssertEqual(MusicLinks.query(for: e), "Nur ein Titel")
    }

    // MARK: - cleanedTitle

    func testCleanedTitleStripsBracketedVersion() {
        XCTAssertEqual(MusicLinks.cleanedTitle("Strobe (Radio Edit)"), "Strobe")
        XCTAssertEqual(MusicLinks.cleanedTitle("Levels [Club Mix]"), "Levels")
    }

    func testCleanedTitleStripsDashedVersion() {
        XCTAssertEqual(MusicLinks.cleanedTitle("Adagio for Strings - Radio Edit"), "Adagio for Strings")
    }

    func testCleanedTitleLeavesPlainTitle() {
        XCTAssertEqual(MusicLinks.cleanedTitle("Clarity"), "Clarity")
    }

    // MARK: - URLs

    func testAppleMusicURLEncodesTermQueryItem() {
        let e = entry(artist: "Daft Punk", title: "Get Lucky", raw: "Daft Punk - Get Lucky")
        let url = MusicLinks.appleMusicSearchURL(for: e)
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        XCTAssertEqual(comps?.host, "music.apple.com")
        XCTAssertEqual(comps?.path, "/search")
        // URLComponents liefert den dekodierten Wert des term-Parameters zurueck.
        let term = comps?.queryItems?.first { $0.name == "term" }?.value
        XCTAssertEqual(term, "Daft Punk Get Lucky")
    }

    func testSpotifyURLPercentEncodesPath() {
        let e = entry(artist: "Daft Punk", title: "Get Lucky", raw: "Daft Punk - Get Lucky")
        let url = MusicLinks.spotifySearchURL(for: e)
        XCTAssertEqual(url.absoluteString, "https://open.spotify.com/search/Daft%20Punk%20Get%20Lucky")
    }
}
