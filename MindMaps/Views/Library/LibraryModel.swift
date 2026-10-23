import SwiftUI
import AppKit

/// Bereich der Seitenleiste.
enum LibrarySection: Hashable {
    case all
    case recent
    case folder(URL)
    case trash
    /// Alle offenen Aufgaben aus allen Dokumenten (M6).
    case tasks
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case name, modified
    var id: String { rawValue }
    var title: String { self == .name ? L("Name") : L("Änderungsdatum") }
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
}

/// Eintrag in der Übersicht: Ordner oder Dokument (bei der Suche mit dem gefundenen Text).
enum LibraryItem: Identifiable {
    case folder(LibraryFolder)
    case document(LibraryDocument, match: String?)

    var id: URL { url }

    var url: URL {
        switch self {
        case .folder(let folder): return folder.url
        case .document(let document, _): return document.url
        }
    }

    var name: String {
        switch self {
        case .folder(let folder): return folder.name
        case .document(let document, _): return document.title
        }
    }

    var document: LibraryDocument? {
        if case .document(let document, _) = self { return document }
        return nil
    }
}

/// Inhalt und Aktionen des Bibliotheksfensters.
final class LibraryModel: ObservableObject {
    @Published private(set) var contents: LibraryContents
    @Published var section: LibrarySection? = .all
    @Published var errorMessage: String?

    private(set) var rootURL: URL
    private var cache: [URL: LibraryDocument] = [:]
    private var watcher: FolderWatcher?
    private var activationObserver: NSObjectProtocol?

    init(rootURL: URL) {
        self.rootURL = rootURL
        self.contents = .empty(rootURL)
    }

    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    /// Bibliotheksordner festlegen (beim Start und nach Änderung in den Einstellungen).
    func open(_ url: URL) {
        rootURL = url
        cache = [:]
        do {
            try LibraryStore.ensureLibrary(at: url)
        } catch {
            errorMessage = L("Der Bibliotheksordner konnte nicht angelegt werden: %@", error.localizedDescription)
        }
        // Beim ersten Start: Anleitung und Lernbeispiele anlegen.
        LearningSamples.installIfNeeded(in: url)
        watcher = FolderWatcher(url: url) { [weak self] in self?.refresh() }
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.refresh() }
        }
        section = .all
        refresh()
    }

    func refresh() {
        var updatedCache = cache
        let scanned = LibraryScanner.scan(rootURL, cache: &updatedCache)
        cache = updatedCache
        if scanned != contents { contents = scanned }
        // Spotlight: neue und geänderte Dokumente melden (M9).
        let documents = scanned.documents
        MainActor.assumeIsolated { SpotlightIndexer.update(documents) }
    }

    // MARK: - Was angezeigt wird

    var folderOptions: [FolderEntry] {
        contents.root.flattened()
    }

    /// Ordner, in dem neue Dokumente und Ordner landen.
    var currentFolder: URL {
        if case .folder(let url)? = section { return url }
        return rootURL
    }

    func items(search: String, sort: LibrarySort) -> [LibraryItem] {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return sorted(contents.documents.compactMap { doc in
                doc.match(search).map { LibraryItem.document(doc, match: $0) }
            }, by: sort)
        }
        switch section ?? .all {
        case .all:
            return sorted(contents.documents.map { .document($0, match: nil) }, by: sort)
        case .recent:
            return recentDocuments.map { .document($0, match: nil) }
        case .folder(let url):
            let key = url.standardizedFileURL.path
            let subfolders = (folder(at: url)?.children ?? []).map(LibraryItem.folder)
            let documents = contents.documents
                .filter { $0.folderURL.standardizedFileURL.path == key }
                .map { LibraryItem.document($0, match: nil) }
            return subfolders + sorted(documents, by: sort)
        case .trash, .tasks:
            return []
        }
    }

    private func sorted(_ items: [LibraryItem], by sort: LibrarySort) -> [LibraryItem] {
        items.sorted { a, b in
            switch sort {
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                return (a.document?.modified ?? .distantPast) > (b.document?.modified ?? .distantPast)
            }
        }
    }

    /// Zuletzt geöffnete Dokumente (auch außerhalb der Bibliothek), neueste zuerst.
    var recentDocuments: [LibraryDocument] {
        NSDocumentController.shared.recentDocumentURLs.compactMap { url in
            let key = url.standardizedFileURL
            return contents.documents.first { $0.url.standardizedFileURL == key }
                ?? LibraryScanner.loadDocument(at: url)
        }
    }

    func folder(at url: URL) -> LibraryFolder? {
        let key = url.standardizedFileURL.path
        return contents.root.flattened().first { $0.folder.path == key }?.folder
    }

    /// Die URL, mit der die Seitenleiste den Ordner kennt (gleicher Pfad, evtl. mit „/“ am Ende).
    func canonicalFolderURL(_ url: URL) -> URL {
        folder(at: url)?.url ?? url
    }

    /// Ort relativ zur Bibliothek, z. B. „Studium › Biologie“.
    func location(of url: URL) -> String {
        let relative = LibraryStore.relativePath(of: url.deletingLastPathComponent(), in: rootURL)
        return relative.isEmpty ? contents.root.name : relative.replacingOccurrences(of: "/", with: " › ")
    }

    func isInsideLibrary(_ url: URL) -> Bool {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root + "/")
    }

    // MARK: - Aktionen

    /// Führt eine Datei-Aktion aus, zeigt Fehler an und liest die Bibliothek neu ein.
    @discardableResult
    func perform<T>(_ action: () throws -> T) -> T? {
        defer { refresh() }
        do {
            return try action()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createDocument(from template: DocumentTemplate) -> URL? {
        perform { try LibraryStore.createDocument(template.makeDocument(), named: template.fileName, in: currentFolder) }
    }

    func createFolder() -> URL? {
        perform { try LibraryStore.createFolder(in: currentFolder) }
    }

    /// Dokumente mit offenen Aufgaben, sortiert nach Titel.
    var documentsWithOpenTasks: [DocumentTasks] {
        contents.documents
            .map { DocumentTasks(document: $0, tasks: $0.data.root.openTasks()) }
            .filter { !$0.tasks.isEmpty }
            .sorted { $0.document.title.localizedStandardCompare($1.document.title) == .orderedAscending }
    }

    var openTaskCount: Int {
        contents.documents.reduce(0) { $0 + $1.data.root.openTasks().count }
    }

    func createLearningSamples() {
        if let folder = perform({ try LearningSamples.create(in: rootURL) }) {
            section = .folder(canonicalFolderURL(folder))
        }
    }

    func createSamples() {
        if let folder = perform({ try SampleLibrary.create(in: rootURL) }) {
            section = .folder(canonicalFolderURL(folder))
        }
    }

    /// Verschiebt (innerhalb der Bibliothek) oder kopiert (von außerhalb) Einträge in einen Ordner.
    @discardableResult
    func drop(_ urls: [URL], into folder: URL) -> Bool {
        let accepted = urls.filter { url in
            isInsideLibrary(url) || url.pathExtension == LibraryScanner.documentExtension
                || MindMapImporter.canImport(url)
        }
        guard !accepted.isEmpty else { return false }
        perform {
            for url in accepted {
                if isInsideLibrary(url) {
                    try LibraryStore.move(url, to: folder)
                } else if url.pathExtension == LibraryScanner.documentExtension {
                    try LibraryStore.copy(url, to: folder)
                } else {
                    // Markdown, OPML, … von außen: als neue Mindmap importieren.
                    try LibraryStore.createDocument(MindMapImporter.importFile(at: url),
                                                    named: ImportController.documentName(for: url), in: folder)
                }
            }
        }
        return true
    }

    func move(_ url: URL, to folder: URL) {
        perform { try LibraryStore.move(url, to: folder) }
    }

    func rename(_ url: URL, to name: String) {
        var wasSelectedFolder = false
        if case .folder(let selected)? = section {
            wasSelectedFolder = selected.standardizedFileURL.path == url.standardizedFileURL.path
        }
        if let renamed = perform({ try LibraryStore.rename(url, to: name) }), wasSelectedFolder {
            section = .folder(canonicalFolderURL(renamed))
        }
    }

    func moveToTrash(_ urls: [URL]) {
        if case .folder(let selected)? = section,
           urls.contains(where: { selected.standardizedFileURL.path.hasPrefix($0.standardizedFileURL.path) }) {
            section = .all
        }
        perform {
            for url in urls { try LibraryStore.moveToTrash(url, libraryRoot: rootURL) }
        }
    }

    func restore(_ item: TrashedItem) {
        perform { try LibraryStore.restore(item.url, libraryRoot: rootURL) }
    }

    func deletePermanently(_ item: TrashedItem) {
        perform { try LibraryStore.deletePermanently(item.url, libraryRoot: rootURL) }
    }

    func emptyTrash() {
        perform { try LibraryStore.emptyTrash(libraryRoot: rootURL) }
    }

    func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Ein Dokument mit seinen offenen Aufgaben (Bibliothek › Aufgaben).
struct DocumentTasks: Identifiable {
    let document: LibraryDocument
    let tasks: [TaskEntry]
    var id: URL { document.url }
}
