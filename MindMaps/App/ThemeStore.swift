import Foundation

/// Lädt die eingebauten Themes aus Themes.json im App-Bundle.
enum ThemeStore {
    static let catalog: ThemeCatalog = {
        guard let url = Bundle.main.url(forResource: "Themes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? ThemeCatalog.decode(data),
              !catalog.themes.isEmpty else {
            return ThemeCatalog(formatVersion: 1, themes: [.fallback])
        }
        // Namen und Beschreibungen in der Sprache der Oberfläche (M12).
        var localized = catalog
        for index in localized.themes.indices {
            localized.themes[index].name = L(localized.themes[index].name)
            localized.themes[index].description = L(localized.themes[index].description)
        }
        return localized
    }()

    /// Eingebautes oder eigenes Thema; unbekannte IDs bekommen das erste eingebaute.
    static func theme(withID id: String) -> Theme {
        if let builtIn = catalog.themes.first(where: { $0.id == id }) { return builtIn }
        if let own = ThemeLibrary.themes().first(where: { $0.id == id }) { return own }
        return catalog.theme(withID: id)
    }

    /// Thema eines Dokuments: das mitgespeicherte (eigene oder angepasste) Thema, sonst das eingebaute (M8).
    static func theme(for data: MindMapDocumentData) -> Theme {
        data.customTheme ?? theme(withID: data.themeID)
    }

    static func isBuiltIn(_ id: String) -> Bool {
        catalog.themes.contains { $0.id == id }
    }

    /// Unverändertes Original eines Themas (eingebaut oder aus „Eigene Themen“), falls vorhanden.
    static func original(withID id: String, defaults: UserDefaults = .standard) -> Theme? {
        catalog.themes.first { $0.id == id } ?? ThemeLibrary.themes(defaults: defaults).first { $0.id == id }
    }
}

/// Eigene Themes (M8). Sie liegen in den Einstellungen der App – Ansichten beobachten sie
/// mit `@AppStorage(ThemeLibrary.key)` – und lassen sich als `.mindmapstheme`-Datei weitergeben.
enum ThemeLibrary {
    static let key = "customThemes"
    static let fileExtension = "mindmapstheme"

    enum ThemeFileError: LocalizedError {
        case unreadable
        var errorDescription: String? { L("Die Datei enthält kein MindMaps-Thema.") }
    }

    /// Inhalt einer `.mindmapstheme`-Datei.
    private struct ThemeFile: Codable {
        var formatVersion: Int
        var theme: Theme
    }

    static func themes(defaults: UserDefaults = .standard) -> [Theme] {
        decode(defaults.string(forKey: key) ?? "")
    }

    static func decode(_ json: String) -> [Theme] {
        guard !json.isEmpty, let data = json.data(using: .utf8),
              let themes = try? JSONDecoder().decode([Theme].self, from: data) else { return [] }
        return themes
    }

    static func encode(_ themes: [Theme]) -> String {
        guard let data = try? JSONEncoder().encode(themes) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ themes: [Theme], defaults: UserDefaults = .standard) {
        defaults.set(encode(themes), forKey: key)
    }

    /// Nimmt ein Thema auf; eines mit gleicher ID wird ersetzt.
    static func add(_ theme: Theme, defaults: UserDefaults = .standard) {
        var list = themes(defaults: defaults)
        if let index = list.firstIndex(where: { $0.id == theme.id }) {
            list[index] = theme
        } else {
            list.append(theme)
        }
        save(list, defaults: defaults)
    }

    static func remove(id: String, defaults: UserDefaults = .standard) {
        save(themes(defaults: defaults).filter { $0.id != id }, defaults: defaults)
    }

    /// Neues eigenes Thema aus einem vorhandenen (z. B. dem angepassten Thema eines Dokuments).
    static func makeTheme(from theme: Theme, name: String) -> Theme {
        var own = theme
        own.id = "eigen-" + UUID().uuidString.lowercased()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        own.name = trimmed.isEmpty ? L("Eigenes Thema") : trimmed
        own.description = L("Eigenes Thema")
        return own
    }

    // MARK: - Datei

    static func fileData(for theme: Theme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(ThemeFile(formatVersion: 1, theme: theme))
    }

    /// Liest eine Theme-Datei. Hat das Thema die ID eines eingebauten Themas, bekommt es eine neue.
    static func theme(fromFile data: Data) throws -> Theme {
        let decoder = JSONDecoder()
        var theme: Theme
        if let file = try? decoder.decode(ThemeFile.self, from: data) {
            theme = file.theme
        } else if let bare = try? decoder.decode(Theme.self, from: data) {
            theme = bare
        } else {
            throw ThemeFileError.unreadable
        }
        if ThemeStore.isBuiltIn(theme.id) || theme.id.isEmpty {
            theme.id = "eigen-" + UUID().uuidString.lowercased()
        }
        return theme
    }
}
