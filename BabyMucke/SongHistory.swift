import Foundation

// Ein gehoerter Titel: Sender, ICY-Rohtext, optional aufgeteilt in Interpret
// und Titel, plus Start/Ende. `end == nil` bedeutet: Der Titel laeuft gerade.
struct SongEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var station: String
    var raw: String
    var artist: String?
    var title: String?
    var start: Date
    var end: Date?

    static func split(_ s: String) -> (artist: String?, title: String?) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: " - ") {
            let a = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let b = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return (a.isEmpty ? nil : a, b.isEmpty ? nil : b)
        }
        return (nil, t.isEmpty ? nil : t)
    }
}

// Fuehrt den lokalen Verlauf. Beim Songwechsel, Senderwechsel oder Stop wird
// der offene Eintrag geschlossen. Kurze Fragmente werden wie in der Mac-App
// entfernt, damit Puffer- und Senderwechsel-Glitches den Verlauf nicht fluten.
@MainActor
final class SongHistory: ObservableObject {
    @Published private(set) var entries: [SongEntry] = []

    private let fileURL: URL
    private let maxEntries = 2000
    private let shortImmediate: TimeInterval = 5
    private let shortLaunchQuit: TimeInterval = 20

    // `directory` ist standardmaessig der App-Support-Ordner und wird nur fuer
    // Tests injiziert, damit diese nicht auf der gemeinsamen verlauf.json arbeiten.
    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BabyMucke", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("verlauf.json")
        load()
    }

    func note(station: String, raw: String, at date: Date = Date()) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let last = entries.last, last.end == nil,
           last.station == station, last.raw == text {
            return
        }
        closeCurrent(at: date)
        let (artist, title) = SongEntry.split(text)
        entries.append(SongEntry(station: station, raw: text,
                                 artist: artist, title: title, start: date))
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        save()
    }

    func closeCurrent(at date: Date = Date()) {
        var changed = false
        if let i = entries.indices.last, entries[i].end == nil {
            entries[i].end = date
            changed = true
        }
        if removeShort(shortImmediate) { changed = true }
        if changed { save() }
    }

    func pruneOnLaunchOrQuit() {
        if removeShort(shortLaunchQuit) { save() }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    // Verlaufs-Eintraege entfernen, deren Ende (bzw. Start, falls noch laufend)
    // vor `cutoff` liegt. In der Mac-App loescht derselbe Button zusaetzlich
    // Aufnahmen; die gibt es auf iOS nicht, hier also nur die Eintraege.
    func remove(olderThan cutoff: Date) {
        let before = entries.count
        entries.removeAll { ($0.end ?? $0.start) < cutoff }
        if entries.count != before { save() }
    }

    func delete(_ entry: SongEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    @discardableResult
    private func removeShort(_ maxSeconds: TimeInterval) -> Bool {
        let before = entries.count
        entries.removeAll { e in
            guard let end = e.end else { return false }
            return end.timeIntervalSince(e.start) < maxSeconds
        }
        return entries.count != before
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.iso.decode([SongEntry].self, from: data)
        else { return }
        entries = decoded
        closeCurrent()
        pruneOnLaunchOrQuit()
    }

    private func save() {
        guard let data = try? JSONEncoder.isoPretty.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    static var isoPretty: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
