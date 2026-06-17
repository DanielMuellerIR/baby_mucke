import Foundation

// Baut Such-URLs fuer Apple Music und Spotify. Fuer den MVP nutzen wir bewusst
// oeffentliche Universal Links statt API-Zugriff mit Authentifizierung.
enum MusicLinks {
    static func query(for entry: SongEntry) -> String {
        if let artist = entry.artist, let title = entry.title {
            return "\(artist) \(cleanedTitle(title))"
        }
        return cleanedTitle(entry.raw)
    }

    static func appleMusicSearchURL(for entry: SongEntry) -> URL {
        var c = URLComponents(string: "https://music.apple.com/search")!
        c.queryItems = [.init(name: "term", value: query(for: entry))]
        return c.url ?? URL(string: "https://music.apple.com/search")!
    }

    static func spotifySearchURL(for entry: SongEntry) -> URL {
        let disallowed = CharacterSet(charactersIn: "/?#")
        let allowed = CharacterSet.urlPathAllowed.subtracting(disallowed)
        let encoded = query(for: entry).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://open.spotify.com/search/\(encoded)")
            ?? URL(string: "https://open.spotify.com/search")!
    }

    // Mix- und Versionszusaetze verschlechtern Suchtreffer oft. Die Regex ist
    // aus der Mac-App uebernommen, aber hier nur fuer Such-URLs genutzt.
    static func cleanedTitle(_ title: String) -> String {
        var t = title
        let bracket = #"\s*[\(\[][^\(\)\[\]]*\b(extended|original|radio|club|edit|remix|mix|version|bootleg|vip|instrumental|acoustic|live|remaster[a-z]*)\b[^\(\)\[\]]*[\)\]]"#
        t = t.replacingOccurrences(of: bracket, with: "", options: [.regularExpression, .caseInsensitive])
        let dash = #"\s[-–—]\s.*\b(mix|remix|edit|version)\b.*$"#
        t = t.replacingOccurrences(of: dash, with: "", options: [.regularExpression, .caseInsensitive])
        return t.trimmingCharacters(in: .whitespaces)
    }
}
