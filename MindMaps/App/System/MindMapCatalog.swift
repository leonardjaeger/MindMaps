import AppKit

/// Findet Dokumente für Kurzbefehle, Siri und Spotlight (M9): in der Bibliothek, zuletzt benutzt, offen.
@MainActor
enum MindMapCatalog {
    enum CatalogError: LocalizedError {
        case noDocument
        var errorDescription: String? {
            L("Es gibt noch keine Mindmap. Lege zuerst eine an – in der App oder mit „Neue Mindmap“.")
        }
    }

    static var libraryURL: URL {
        LibraryStore.libraryURL(fromStoredPath: UserDefaults.standard.string(forKey: "libraryPath") ?? "")
    }

    /// Alle Dokumente der Bibliothek (ohne Papierkorb).
    static func libraryDocuments() -> [LibraryDocument] {
        var cache: [URL: LibraryDocument] = [:]
        return LibraryScanner.scan(libraryURL, cache: &cache).documents
    }

    /// Treffer im Titel zuerst, dann im Inhalt; jeweils die zuletzt geänderten oben.
    static func search(_ query: String, in documents: [LibraryDocument]) -> [LibraryDocument] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return documents.sorted { $0.modified > $1.modified } }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let inTitle = documents.filter { $0.title.range(of: q, options: options) != nil }
        let titleURLs = Set(inTitle.map(\.url))
        let inContent = documents.filter { !titleURLs.contains($0.url) && $0.match(q) != nil }
        return inTitle.sorted { $0.modified > $1.modified } + inContent.sorted { $0.modified > $1.modified }
    }

    /// Zuletzt benutzt: das neueste Dokument aus „Zuletzt benutzt“ von macOS, das es noch gibt –
    /// sonst das zuletzt geänderte der Bibliothek.
    static func lastUsed(recent: [URL], documents: [LibraryDocument]) -> URL? {
        for url in recent where url.pathExtension == LibraryScanner.documentExtension {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(MindMapCodec.documentFileName).path) {
                return url
            }
        }
        return documents.max { $0.modified < $1.modified }?.url
    }

    static func lastUsedURL() throws -> URL {
        guard let url = lastUsed(recent: NSDocumentController.shared.recentDocumentURLs,
                                 documents: libraryDocuments()) else { throw CatalogError.noDocument }
        return url
    }

    /// Das gewählte Dokument oder – ohne Auswahl – das zuletzt benutzte.
    static func resolve(_ entity: MindMapEntity?) throws -> URL {
        if let entity { return entity.url }
        return try lastUsedURL()
    }

    /// Inhalt eines Dokuments: aus dem offenen Fenster (mit ungesicherten Änderungen) oder von der Platte.
    static func load(_ url: URL) throws -> (data: MindMapDocumentData, assets: [String: Data]) {
        if let open = OpenDocuments.find(url) {
            return (open.document.data, open.document.assets)
        }
        let wrapper = try FileWrapper(url: url, options: .immediate)
        return try MindMapFile.readPackage(wrapper)
    }

    /// Ändert ein Dokument: im offenen Fenster (mit Rückgängig) oder direkt in der Datei.
    static func modify(_ url: URL, actionName: String, _ change: (inout MindMapDocumentData) throws -> Void) throws {
        if let open = OpenDocuments.find(url) {
            var data = open.document.data
            try change(&data)
            open.document.apply(actionName, undoManager: open.undoManager) { $0 = data }
            return
        }
        var coordinationError: NSError?
        var thrown: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [],
                                                         error: &coordinationError) { target in
            do {
                var data = try MindMapPackage.read(target)
                try change(&data)
                try MindMapPackage.write(data, to: target)
            } catch {
                thrown = error
            }
        }
        if let error = coordinationError ?? thrown { throw error }
    }

    static func title(of url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    static func entity(for url: URL) -> MindMapEntity {
        let folder = url.deletingLastPathComponent()
        let relative = LibraryStore.relativePath(of: folder, in: libraryURL)
        let location: String
        if folder.standardizedFileURL.path == libraryURL.standardizedFileURL.path {
            location = L("Bibliothek")
        } else if !relative.isEmpty {
            location = relative.replacingOccurrences(of: "/", with: " › ")
        } else {
            location = folder.lastPathComponent
        }
        return MindMapEntity(id: url.standardizedFileURL.path, title: title(of: url), location: location)
    }

    static func open(_ url: URL, node: UUID? = nil) {
        if let node { PendingSelection.set(node, for: url) }
        NSApp.activate()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}

/// Offene Dokumentfenster – damit Kurzbefehle und Erinnerungen ein offenes Dokument
/// im Fenster ändern (mit Rückgängig) statt an der Datei vorbei.
@MainActor
enum OpenDocuments {
    struct Entry {
        let document: MindMapFile
        let undoManager: UndoManager?
    }

    private final class Registration {
        weak var document: MindMapFile?
        weak var undoManager: UndoManager?
        var url: URL?
        init(document: MindMapFile, undoManager: UndoManager?, url: URL?) {
            self.document = document
            self.undoManager = undoManager
            self.url = url
        }
    }

    private static var registrations: [ObjectIdentifier: Registration] = [:]

    static func register(_ document: MindMapFile, url: URL?, undoManager: UndoManager?) {
        registrations = registrations.filter { $0.value.document != nil }
        registrations[ObjectIdentifier(document)] = Registration(document: document, undoManager: undoManager, url: url)
    }

    static func unregister(_ document: MindMapFile) {
        registrations[ObjectIdentifier(document)] = nil
    }

    static func find(_ url: URL) -> Entry? {
        let key = url.standardizedFileURL.path
        for registration in registrations.values {
            guard let document = registration.document,
                  registration.url?.standardizedFileURL.path == key else { continue }
            return Entry(document: document, undoManager: registration.undoManager)
        }
        return nil
    }
}
