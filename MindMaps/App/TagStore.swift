import Foundation

/// Der Tag-Katalog der App (Namen und Farben), gespeichert in den Einstellungen.
/// Ansichten beobachten ihn mit `@AppStorage(TagStore.key)` und zeichnen sich bei Änderungen neu.
enum TagStore {
    static let key = "tagCatalog"

    static var catalog: TagCatalog {
        decode(UserDefaults.standard.string(forKey: key) ?? "")
    }

    static func decode(_ json: String) -> TagCatalog {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let catalog = try? JSONDecoder().decode(TagCatalog.self, from: data) else {
            return .standard
        }
        return catalog
    }

    static func encode(_ catalog: TagCatalog) -> String {
        guard let data = try? JSONEncoder().encode(catalog) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ catalog: TagCatalog) {
        UserDefaults.standard.set(encode(catalog), forKey: key)
    }

    /// Neues Tag in den Katalog aufnehmen (falls es noch fehlt).
    static func add(_ name: String) {
        var catalog = self.catalog
        if catalog.add(name) { save(catalog) }
    }
}
