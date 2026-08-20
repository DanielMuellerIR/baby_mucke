import Foundation
import os

// Haelt die Senderliste und speichert sie im Application-Support-Ordner.
// Die JSON-Struktur bleibt kompatibel zur Mac-App, damit Listen spaeter einfach
// zwischen beiden Apps geteilt oder migriert werden koennen.
@MainActor
final class StationStore: ObservableObject {
    @Published var stations: [Station] = []

    let dir: URL
    let stationsURL: URL

    private let defaults: UserDefaults
    private let lastPlayedKey = "lastPlayedStationID"

    // `directory` ist standardmaessig der App-Support-Ordner und wird nur fuer
    // Tests injiziert, damit diese nicht auf der gemeinsamen stations.json arbeiten.
    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("BabyMucke", isDirectory: true)
        stationsURL = dir.appendingPathComponent("stations.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadStations()
    }

    var enabledStations: [Station] {
        stations.filter { $0.enabled }
    }

    // codereview-ok: lineare Suche ueber die (kleine) Senderliste ist bewusst so — ein Cache muesste bei jeder Listenaenderung invalidiert werden und waere mehr Komplexitaet als Nutzen (2026-07-08)
    var favorite: Station? {
        stations.first { $0.favorite }
    }

    var lastPlayed: Station? {
        guard let raw = defaults.string(forKey: lastPlayedKey),
              let id = UUID(uuidString: raw) else { return nil }
        // Deaktivierte Sender nicht zurueckgeben — ein zwischenzeitlich
        // deaktivierter Sender soll beim App-Start nicht als "aktiver Sender" gelten.
        return stations.first { $0.id == id && $0.enabled }
    }

    // Der Sender, mit dem die Wiedergabe starten soll, wenn gerade keiner aktiv
    // ist: zuletzt gespielt, sonst der erste der aktivierten Wiedergabeliste.
    // Zentral hier, damit alle Auswahl- und Play-Einstiegspfade dieselbe Wahl treffen.
    var defaultStation: Station? {
        lastPlayed ?? stationsForPlaybackList.first
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

    static let stationsEncoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    static let stationsDecoder = JSONDecoder()

    func loadStations() {
        guard FileManager.default.fileExists(atPath: stationsURL.path) else {
            stations = seededStations()
            saveStations()
            return
        }

        do {
            let data = try Data(contentsOf: stationsURL)
            let list = try Self.stationsDecoder.decode([Station].self, from: data)
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
        } catch {
            Self.log.error("stations.json konnte nicht geladen werden (\(error)), sichere Backup nach stations.json.bak")
            let bakURL = dir.appendingPathComponent("stations.json.bak")
            try? FileManager.default.removeItem(at: bakURL)
            try? FileManager.default.copyItem(at: stationsURL, to: bakURL)
            stations = seededStations()
        }
    }

    func saveStations() {
        do {
            let data = try Self.stationsEncoder.encode(stations)
            try data.write(to: stationsURL, options: .atomic)
        } catch {
            Self.log.error("stations.json konnte nicht gespeichert werden: \(error)")
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
        // Verwaisten lastPlayed-Eintrag bereinigen: eine neu angelegte Station
        // bekaeme eine andere UUID, wuerde aber sonst auf diesen Phantom-Eintrag treffen.
        if defaults.string(forKey: lastPlayedKey) == station.id.uuidString {
            defaults.removeObject(forKey: lastPlayedKey)
        }
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
        let imported = try Self.stationsDecoder.decode([Station].self, from: data)
        let normalized = try normalizedStations(imported)

        // Vor dem Überschreiben bisherige Datei als stations.backup.json sichern
        if FileManager.default.fileExists(atPath: stationsURL.path) {
            let backupURL = dir.appendingPathComponent("stations.backup.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: stationsURL, to: backupURL)
        }

        stations = normalized
        saveStations()
    }

    // MARK: - Seed

    // Logger fuer Bundle-Lade-Fehler (sichtbar in Xcode-Konsole und Console.app).
    private static let log = Logger(subsystem: "de.babymucke.BabyMucke", category: "StationStore")

    private func seededStations() -> [Station] {
        // Nur noch seed-stations.json (seed-stations.example.json wurde entfernt).
        if let url = Bundle.main.url(forResource: "seed-stations", withExtension: "json") {
            do {
                let data = try Data(contentsOf: url)
                let seeds = try Self.stationsDecoder.decode([SeedStation].self, from: data)
                if !seeds.isEmpty { return seeds.map { $0.toStation() } }
                Self.log.warning("seed-stations.json ist leer — falle auf builtinDefaults zurueck")
            } catch {
                // Beschaedigte Bundle-Datei wuerde stillschweigend zur Demoliste fuehren.
                // Hier explizit loggen, damit der Fehler nicht unbemerkt bleibt.
                Self.log.error("seed-stations.json konnte nicht geladen werden: \(error)")
                assertionFailure("seed-stations.json Ladefehler: \(error)")
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
        return (try? StationStore.stationsDecoder.decode([SeedStation].self, from: Data(json.utf8))) ?? []
    }()

    // codereview-ok: Vergleich ueber name UND url ist Absicht — sobald der Nutzer nur EINE der vier Demo-URLs (oder Namen) aendert, schlaegt allSatisfy fehl und die Liste bleibt unangetastet; es gibt keinen Datenverlust (2026-07-08)
    private func isLegacyDemoList(_ list: [Station]) -> Bool {
        let demo = Self.builtinDefaults
        guard list.count == demo.count else { return false }
        return zip(list, demo).allSatisfy { station, seed in
            station.name == seed.name && station.url == seed.url
        }
    }

    // MARK: - Bearbeiten

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
