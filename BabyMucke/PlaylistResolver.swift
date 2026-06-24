import Foundation

// Loest Playlist-URLs (.pls/.m3u/.asx/.xspf, radiotime Tune.ashx) zur
// eigentlichen Stream-URL auf. AVPlayer braucht normalerweise die rohe
// MP3/AAC/HLS-Adresse und kann viele klassische Radio-Playlistcontainer nicht
// direkt als Sender abspielen.
enum PlaylistResolver {
    static func resolve(_ raw: String, depth: Int = 0) async -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        if depth > 3 { return url }
        guard needsResolution(url) else { return url }
        guard let text = await fetchHead(url) else { return url }
        guard let inner = firstMediaURL(in: text) else { return url }
        if inner.absoluteString == url.absoluteString { return url }
        return await resolve(inner.absoluteString, depth: depth + 1)
    }

    static func needsResolution(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        if s.contains(".m3u8") { return false }
        // "-pls" am Ende eines Pfadsegments faengt TuneIn-Endpunkte wie
        // ".../tunein-aac-hd-pls" ab, die eine PLS-Playlist liefern, aber weder auf
        // ".pls" noch "/pls" enden. Bewusst grenzgebunden, damit eine direkte
        // Stream-URL wie "https://my-pls-cdn.example/stream.mp3" nicht faelschlich
        // als Playlist behandelt wird.
        return s.contains(".pls") || s.contains(".m3u") || s.contains(".asx")
            || s.contains(".xspf") || s.contains("tune.ashx") || s.contains("/pls")
            || s.hasSuffix("-pls") || s.contains("-pls?") || s.contains("-pls/")
    }

    // Nur den Kopf der Datei laden: Falls die Heuristik irrt und die URL schon
    // ein Audiostream ist, ziehen wir nicht versehentlich beliebig viele Bytes.
    static func fetchHead(_ url: URL) async -> String? {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        req.setValue("BabyMucke/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 8
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        } catch {
            return nil
        }
    }

    static func firstMediaURL(in text: String) -> URL? {
        // PLS: Zeilen wie "File1=http://..."
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.lowercased().hasPrefix("file"), let eq = l.firstIndex(of: "=") {
                let value = String(l[l.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if let u = URL(string: value), u.scheme?.hasPrefix("http") == true { return u }
            }
        }
        // M3U oder Klartext: erste sinnvolle http-Zeile.
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("[") { continue }
            if l.lowercased().hasPrefix("http"), let u = URL(string: l) { return u }
        }
        // ASX/XSPF: <location>URL</location> oder href="URL" / href='URL'
        // (XML erlaubt beide Anfuehrungszeichen; manche ASX-Dateien nutzen ').
        if let m = firstMatch(text, pattern: "(?:<location>|href=[\"'])\\s*(https?://[^<\"'\\s]+)") {
            return URL(string: m)
        }
        return nil
    }

    static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
