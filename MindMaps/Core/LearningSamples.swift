import Foundation

/// Anleitung und Lernbeispiele (Biologie, Jura, Medizin, Informatik, Geschichte, Politik).
/// Auf Englisch gibt es nur die Anleitung („Guide“, seit M12).
///
/// Die Inhalte liegen als `Lernbeispiele.json` in der App. Beim ersten Öffnen der Bibliothek
/// werden sie als echte Dokumente in den Ordner „Lernbeispiele“ gelegt.
enum LearningSamples {
    static let resourceName = "Lernbeispiele"
    /// Englische Fassung (M12): nur die Anleitung – die Lernbeispiele selbst sind deutsche Lerninhalte.
    static let englishResourceName = "Lernbeispiele-en"
    static let installedKey = "learningSamplesInstalled"

    struct Package: Decodable {
        struct Entry: Decodable {
            let name: String
            let document: MindMapDocumentData
        }
        let folder: String
        let documents: [Entry]
    }

    enum SampleError: LocalizedError {
        case missingResource
        var errorDescription: String? { L("Die Lernbeispiele fehlen in der App.") }
    }

    /// Lädt die Beispiele aus der App (oder – in Tests ohne App – aus dem Quellordner).
    static func load(bundle: Bundle = .main, language: String = Localization.language) throws -> Package {
        let resourceName = language == "en" ? Self.englishResourceName : Self.resourceName
        var url = bundle.url(forResource: resourceName, withExtension: "json")
        if url == nil {
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/\(resourceName).json")
            if FileManager.default.fileExists(atPath: source.path) { url = source }
        }
        guard let url else { throw SampleError.missingResource }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Package.self, from: Data(contentsOf: url))
    }

    /// Legt den Ordner „Lernbeispiele“ (bzw. „Lernbeispiele 2“ …) mit allen Dokumenten an.
    @discardableResult
    static func create(in root: URL, bundle: Bundle = .main) throws -> URL {
        let package = try load(bundle: bundle)
        try LibraryStore.ensureLibrary(at: root)
        let folder = LibraryStore.uniqueURL(named: package.folder, pathExtension: nil, in: root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for entry in package.documents {
            var document = entry.document
            document.modifiedAt = MindMapDocumentData.now()
            try LibraryStore.createDocument(document, named: entry.name, in: folder)
        }
        return folder
    }

    /// Beim ersten Start einmal anlegen (auch wenn die Bibliothek schon andere Dokumente enthält).
    static func installIfNeeded(in root: URL, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: installedKey) else { return }
        if (try? create(in: root)) != nil {
            defaults.set(true, forKey: installedKey)
        }
    }
}
