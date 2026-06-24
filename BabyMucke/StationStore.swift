import Foundation

// Haelt die Senderliste und speichert sie im Application-Support-Ordner.
// Die JSON-Struktur bleibt kompatibel zur Mac-App, damit Listen spaeter einfach
// zwischen beiden Apps geteilt oder migriert werden koennen.
@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [Station] = []

    let dir: URL
    let stationsURL: URL

    private let defaults = UserDefaults.standard
    private let lastPlayedKey = "lastPlayedStationID"

    // `directory` ist standardmaessig der App-Support-Ordner und wird nur fuer
    // Tests injiziert, damit diese nicht auf der gemeinsamen stations.json arbeiten.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("BabyMucke", isDirectory: true)
        stationsURL = dir.appendingPathComponent("stations.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadStations()
    }

    var enabledStations: [Station] {
        stations.filter { $0.enabled }
    }

    var favorite: Station? {
        stations.first { $0.favorite }
    }

    var lastPlayed: Station? {
        guard let raw = defaults.string(forKey: lastPlayedKey),
              let id = UUID(uuidString: raw) else { return nil }
        return stations.first { $0.id == id }
    }

    // Reihenfolge fuer die Hauptliste: Favorit, zuletzt gespielt, danach alle
    // sichtbaren Sender in gespeicherter Reihenfolge ohne Dubletten.
    var stationsForPlaybackList: [Station] {
        var seen = Set<UUID>()
        var ordered: [Station] = []
        func append(_ station: Station?) {
            guard let station, station.enabled, !seen.contains(station.id) else { return }
            seen.insert(station.id)
            ordered.append(station)
        }
        append(favorite)
        append(lastPlayed)
        for station in enabledStations { append(station) }
        return ordered
    }

    func markPlayed(_ station: Station) {
        defaults.set(station.id.uuidString, forKey: lastPlayedKey)
    }

    // MARK: - Laden / Speichern

    func loadStations() {
        if let data = try? Data(contentsOf: stationsURL),
           let list = try? JSONDecoder().decode([Station].self, from: data),
           !list.isEmpty {
            // Fruehe Test-Builds haben eine kleine 4-Sender-Demoliste persistiert.
            // Diese unberuehrte Demoliste ersetzen wir durch den gebuendelten Default,
            // damit bestehende Beta-Installationen ebenfalls mit Daniels Senderliste starten.
            // Sobald ein Nutzer die Liste bearbeitet hat, bleibt sie unangetastet.
            if isLegacyDemoList(list) {
                stations = seededStations()
                saveStations()
            } else {
                stations = list
            }
            return
        }
        stations = seededStations()
        saveStations()
    }

    func saveStations() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(stations) {
            try? data.write(to: stationsURL, options: .atomic)
        }
    }

    func upsert(_ station: Station) {
        var cleaned = station
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.url = cleaned.url.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.name.isEmpty, !cleaned.url.isEmpty else { return }
        if let i = stations.firstIndex(where: { $0.id == cleaned.id }) {
            stations[i] = cleaned
        } else {
            stations.append(cleaned)
        }
        saveStations()
    }

    func delete(_ station: Station) {
        stations.removeAll { $0.id == station.id }
        saveStations()
    }

    func importStations(fromFile url: URL) throws {
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        let imported = try JSONDecoder().decode([Station].self, from: data)
        stations = try normalizedStations(imported)
        saveStations()
    }

    // MARK: - Seed

    private func seededStations() -> [Station] {
        let candidates = [
            ("seed-stations", "json"),
            ("seed-stations.example", "json")
        ]
        for candidate in candidates {
            if let url = Bundle.main.url(forResource: candidate.0, withExtension: candidate.1),
               let data = try? Data(contentsOf: url),
               let seeds = try? JSONDecoder().decode([SeedStation].self, from: data),
               !seeds.isEmpty {
                return seeds.map { $0.toStation() }
            }
        }
        return Self.builtinDefaults.map { $0.toStation() }
    }

    static let builtinDefaults: [SeedStation] = {
        let json = """
        [
          {"name":"Smooth Chill","url":"https://media-ssl.musicradio.com/ChillMP3","favorite":true},
          {"name":"Austrian Rock Radio","url":"http://live.antenne.at/arr"},
          {"name":"Radio BOB","url":"http://live6.infonetmedia.si/Europa05"},
          {"name":"Deep House Radio","url":"http://62.210.105.16:7000/stream"}
        ]
        """
        return (try? JSONDecoder().decode([SeedStation].self, from: Data(json.utf8))) ?? []
    }()

    private func isLegacyDemoList(_ list: [Station]) -> Bool {
        let demo = Self.builtinDefaults
        guard list.count == demo.count else { return false }
        return zip(list, demo).allSatisfy { station, seed in
            station.name == seed.name && station.url == seed.url
        }
    }

    // MARK: - Bearbeiten

    func setFavorite(_ station: Station) {
        for i in stations.indices {
            stations[i].favorite = (stations[i].id == station.id)
        }
        saveStations()
    }

    func toggleEnabled(_ station: Station) {
        guard let i = stations.firstIndex(where: { $0.id == station.id }) else { return }
        stations[i].enabled.toggle()
        saveStations()
    }

    private func normalizedStations(_ imported: [Station]) throws -> [Station] {
        var seen = Set<UUID>()
        let cleaned = imported.compactMap { station -> Station? in
            var s = station
            s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            s.url = s.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.name.isEmpty, !s.url.isEmpty else { return nil }

            // Handgepflegte JSON-Dateien koennen IDs kopieren. Doppelte IDs
            // wuerden Auswahl, Verlauf und Bearbeiten durcheinanderbringen.
            if seen.contains(s.id) {
                s.id = UUID()
            }
            seen.insert(s.id)
            return s
        }
        guard !cleaned.isEmpty else { throw StationImportError.emptyOrInvalid }
        return cleaned
    }
}

enum StationImportError: LocalizedError {
    case emptyOrInvalid

    var errorDescription: String? {
        switch self {
        case .emptyOrInvalid:
            return String(localized: "Keine gültigen Sender gefunden.")
        }
    }
}
