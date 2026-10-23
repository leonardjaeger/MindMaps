import Foundation

/// Ein Dokument in der Bibliothek.
struct LibraryDocument: Identifiable, Equatable {
    let url: URL
    let title: String
    /// Änderungsdatum der `document.json`.
    let modified: Date
    let data: MindMapDocumentData

    var id: URL { url }
    var folderURL: URL { url.deletingLastPathComponent() }
    var nodeCount: Int { data.root.nodeCount }

    /// Findet `query` im Titel oder in einem Knotentext (ohne Groß-/Kleinschreibung und Akzente).
    /// Liefert den gefundenen Text – beim Titel den Titel selbst.
    func match(_ query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if title.range(of: q, options: options) != nil { return title }
        return LibraryDocument.texts(of: data.root).first { $0.range(of: q, options: options) != nil }
    }

    /// Alle Knotentexte in Lesereihenfolge.
    static func texts(of node: Node) -> [String] {
        [node.text] + node.children.flatMap { texts(of: $0) }
    }
}

/// Ein Ordner der Bibliothek mit seinen Unterordnern.
struct LibraryFolder: Identifiable, Hashable {
    let url: URL
    let name: String
    /// `nil` statt leer, damit die Seitenleiste keinen Aufklapp-Pfeil zeigt.
    var children: [LibraryFolder]?

    var id: URL { url }

    /// Dieser Ordner und alle Unterordner, mit Tiefe (für das Menü „Bewegen nach“).
    func flattened(depth: Int = 0) -> [FolderEntry] {
        [FolderEntry(folder: self, depth: depth)] + (children ?? []).flatMap { $0.flattened(depth: depth + 1) }
    }

    /// Pfad ohne abschließenden „/“ – zum Vergleichen von Ordner-URLs.
    var path: String { url.standardizedFileURL.path }
}

/// Ordner mit seiner Tiefe im Baum.
struct FolderEntry: Identifiable {
    let folder: LibraryFolder
    let depth: Int
    var id: URL { folder.url }
}

/// Ein Eintrag im Papierkorb der Bibliothek.
struct TrashedItem: Identifiable, Equatable {
    let url: URL
    let isFolder: Bool
    /// Ursprünglicher Ordner, relativ zur Bibliothek ("" = oberste Ebene).
    let originalFolder: String

    var id: URL { url }
    var name: String {
        isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }
}

/// Inhalt der Bibliothek nach einem Durchlauf.
struct LibraryContents: Equatable {
    var root: LibraryFolder
    var documents: [LibraryDocument]
    var trash: [TrashedItem]

    static func empty(_ root: URL) -> LibraryContents {
        LibraryContents(root: LibraryFolder(url: root, name: root.lastPathComponent, children: nil),
                        documents: [], trash: [])
    }
}

/// Liest den Bibliotheksordner ein: Unterordner, `.mindmaps`-Dokumente und den Papierkorb.
enum LibraryScanner {
    static let documentExtension = "mindmaps"

    /// `cache` hält bereits gelesene Dokumente; nur geänderte Dateien werden neu gelesen.
    static func scan(_ root: URL, cache: inout [URL: LibraryDocument]) -> LibraryContents {
        var documents: [LibraryDocument] = []
        var seen = Set<URL>()

        func folder(at url: URL) -> LibraryFolder {
            var subfolders: [LibraryFolder] = []
            for item in contents(of: url) {
                if item.pathExtension == documentExtension {
                    let key = item.standardizedFileURL
                    seen.insert(key)
                    if let document = document(at: item, cache: &cache) {
                        documents.append(document)
                    }
                } else if isDirectory(item) {
                    subfolders.append(folder(at: item))
                }
            }
            return LibraryFolder(url: url, name: url.lastPathComponent,
                                 children: subfolders.isEmpty ? nil : subfolders)
        }

        let rootFolder = folder(at: root)
        cache = cache.filter { seen.contains($0.key) }
        return LibraryContents(root: rootFolder, documents: documents, trash: trashedItems(in: root))
    }

    /// Liest ein einzelnes Dokument (z. B. „Zuletzt benutzt“ außerhalb der Bibliothek).
    static func loadDocument(at url: URL) -> LibraryDocument? {
        var cache: [URL: LibraryDocument] = [:]
        return document(at: url, cache: &cache)
    }

    private static func document(at url: URL, cache: inout [URL: LibraryDocument]) -> LibraryDocument? {
        let key = url.standardizedFileURL
        let json = url.appendingPathComponent(MindMapCodec.documentFileName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: json.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        if let cached = cache[key], cached.modified == modified { return cached }
        guard let raw = try? Data(contentsOf: json),
              let data = try? MindMapCodec.decode(raw) else { return nil }
        let document = LibraryDocument(url: url, title: url.deletingPathExtension().lastPathComponent,
                                       modified: modified, data: data)
        cache[key] = document
        return document
    }

    static func trashedItems(in root: URL) -> [TrashedItem] {
        let trash = LibraryStore.trashURL(for: root)
        let origins = LibraryStore.readOrigins(root)
        return contents(of: trash).map { item in
            TrashedItem(url: item,
                        isFolder: item.pathExtension != documentExtension && isDirectory(item),
                        originalFolder: origins[item.lastPathComponent] ?? "")
        }
    }

    /// Sichtbare Einträge eines Ordners, nach Namen sortiert wie im Finder.
    ///
    /// Bewusst ohne `.skipsHiddenFiles`: iCloud Drive markiert Dateien in Ordnern, die nicht
    /// synchronisiert werden (z. B. `.Papierkorb`), selbst als versteckt – der Papierkorb wirkte
    /// dadurch leer, obwohl die Dokumente darin lagen. Ausgeblendet werden nur Namen mit Punkt.
    static func contents(of folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { folder.appendingPathComponent($0) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
