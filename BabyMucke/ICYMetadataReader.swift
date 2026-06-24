import Foundation

// Liest den ICY-Live-Titel (StreamTitle) direkt aus dem Shoutcast/Icecast-
// Stream. AVPlayer spielt zwar den Stream, reicht diese Live-Metadaten aber bei
// vielen Sendern nicht verlaesslich an die App weiter. Deshalb oeffnen wir eine
// zweite leichte Verbindung nur fuer Metadaten.
final class ICYMetadataReader: NSObject, URLSessionDataDelegate {
    var onTitle: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?

    // Eigene serielle Delegate-Queue fuer ALLE Callbacks. Sie wird ueber
    // Session-Wechsel hinweg wiederverwendet, damit Callbacks einer alten und
    // einer frisch gestarteten Session nie nebenlaeufig laufen. Der Parser-Zustand
    // unten wird ausschliesslich auf dieser Queue angefasst (in didReceive ...),
    // nie vom aufrufenden Main-Thread — deshalb braucht er kein Locking.
    private let delegateQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.name = "de.babymucke.icy-metadata"
        return q
    }()

    // Parser-Zustand. Nur auf delegateQueue gelesen/geschrieben (siehe oben).
    private var metaint = 0
    private var skip = 0
    private var inMeta = false
    private var metaLeft = 0
    private var buf = [UInt8]()
    private var lastTitle = ""

    func start(url: URL) {
        stop()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: delegateQueue)
        session = s
        var req = URLRequest(url: url)
        req.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        req.setValue("BabyMucke/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let t = s.dataTask(with: req)
        task = t
        t.resume()
    }

    // Nur Session/Task abbauen (laeuft auf dem aufrufenden Main-Thread). Der
    // Parser-Zustand wird hier bewusst NICHT zurueckgesetzt — das geschieht beim
    // naechsten Stream in didReceive response auf der Delegate-Queue, damit es
    // nie mit einem noch laufenden Callback der alten Session kollidiert.
    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Frischer Stream: Parser-Zustand hier auf der Delegate-Queue zuruecksetzen
        // (statt im main-seitigen stop()), damit kein Datenrennen entsteht.
        metaint = 0
        skip = 0
        inMeta = false
        metaLeft = 0
        buf.removeAll(keepingCapacity: false)
        lastTitle = ""

        let http = response as? HTTPURLResponse
        if let v = http?.value(forHTTPHeaderField: "icy-metaint") ?? http?.value(forHTTPHeaderField: "Icy-MetaInt"),
           let n = Int(v), n > 0 {
            metaint = n
            skip = n
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard metaint > 0 else { return }
        for b in data {
            if !inMeta {
                if skip > 0 {
                    skip -= 1
                    continue
                }
                metaLeft = Int(b) * 16
                if metaLeft == 0 {
                    skip = metaint
                } else {
                    inMeta = true
                    buf.removeAll(keepingCapacity: true)
                }
            } else {
                buf.append(b)
                metaLeft -= 1
                if metaLeft == 0 {
                    parse(buf)
                    inMeta = false
                    skip = metaint
                }
            }
        }
    }

    private func parse(_ bytes: [UInt8]) {
        let startMarker = Array("StreamTitle='".utf8)
        let endMarker = Array("';".utf8)
        guard let s = indexOf(startMarker, in: bytes) else { return }
        let titleStart = s + startMarker.count
        guard let e = indexOf(endMarker, in: bytes, from: titleStart) else { return }
        let titleBytes = Array(bytes[titleStart..<e])
        let title = decodeICY(titleBytes).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != lastTitle else { return }
        lastTitle = title
        DispatchQueue.main.async { self.onTitle?(title) }
    }

    // Viele Sender schicken keine UTF-8-Titel. Die Reihenfolge ist wichtig:
    // Latin-1 akzeptiert jedes Byte und muss deshalb letzter echter Fallback sein.
    private func decodeICY(_ bytes: [UInt8]) -> String {
        let data = Data(bytes)
        if let u = String(data: data, encoding: .utf8), !u.contains("\u{FFFD}") {
            return u
        }
        if looksLikeWindows1251(bytes) {
            let cp1251 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue))
            if let cyr = String(data: data, encoding: String.Encoding(rawValue: cp1251)),
               cyr.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) {
                return cyr
            }
        }
        let cp932 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
        if let sj = String(data: data, encoding: String.Encoding(rawValue: cp932)),
           sj.unicodeScalars.contains(where: { isJapaneseScalar($0.value) }) {
            return sj
        }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: bytes, as: UTF8.self)
    }

    private func looksLikeWindows1251(_ bytes: [UInt8]) -> Bool {
        var run = 0
        for b in bytes {
            if b >= 0xC0 || b == 0xA8 || b == 0xB8 {
                run += 1
                if run >= 3 { return true }
            } else {
                run = 0
            }
        }
        return false
    }

    private func isJapaneseScalar(_ v: UInt32) -> Bool {
        return (0x3040...0x30FF).contains(v)
            || (0xFF61...0xFF9F).contains(v)
            || (0x4E00...0x9FFF).contains(v)
    }

    private func indexOf(_ needle: [UInt8], in haystack: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let last = haystack.count - needle.count
        var i = from
        while i <= last {
            var match = true
            for j in 0..<needle.count where haystack[i + j] != needle[j] {
                match = false
                break
            }
            if match { return i }
            i += 1
        }
        return nil
    }
}
