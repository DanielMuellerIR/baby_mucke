import Foundation

// Datenmodell eines Radiosenders.
// `id` bleibt stabil, damit Favorit, Verlauf und zuletzt gespielter Sender auch
// nach Umbenennen oder Umsortieren zuverlaessig zusammenfinden.
struct Station: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var enabled: Bool = true
    var favorite: Bool = false

    init(id: UUID = UUID(), name: String, url: String, enabled: Bool = true, favorite: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.enabled = enabled
        self.favorite = favorite
    }

    // Toleranter Decoder: handgepflegte JSON-Dateien duerfen Felder weglassen,
    // ohne dass die komplette Senderliste unbrauchbar wird.
    enum CodingKeys: String, CodingKey { case id, name, url, enabled, favorite }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
    }
}

// Eintrag aus einer gebuendelten Seed-Datei. Er hat noch keine stabile UUID,
// weil diese erst beim Import in die lokale stations.json vergeben wird.
struct SeedStation: Decodable {
    let name: String
    let url: String
    var enabled: Bool = true
    var favorite: Bool = false

    enum CodingKeys: String, CodingKey { case name, url, enabled, favorite }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(String.self, forKey: .url)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
    }

    func toStation() -> Station {
        Station(name: name, url: url, enabled: enabled, favorite: favorite)
    }
}

// App-Version. Wird aus dem Bundle gelesen (CFBundleShortVersionString =
// $(MARKETING_VERSION)), damit sie nicht gegenueber project.pbxproj/VERSION
// driften kann. Einziger Konsument ist der HTTP-User-Agent in PlaylistResolver
// und ICYMetadataReader.
enum AppInfo {
    static let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.11"
}
