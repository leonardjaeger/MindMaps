import AppKit
import UniformTypeIdentifiers

/// Importieren (Ablage › Importieren …, ⌘ I): Markdown, OPML, Klartext, FreeMind, TextBundle.
/// Jede Datei wird ein neues Dokument in der Bibliothek und öffnet sich gleich.
@MainActor
enum ImportController {
    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .mindMapsDocument]
        for ext in MindMapImporter.supportedExtensions {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }

    /// Fragt nach Dateien, legt die Dokumente in `folder` an und öffnet sie.
    static func chooseAndImport(into folder: URL) {
        let panel = NSOpenPanel()
        panel.title = L("Importieren")
        panel.message = L("Markdown, OPML, Klartext, FreeMind oder TextBundle – jede Datei wird eine neue Mindmap.")
        panel.prompt = L("Importieren")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = contentTypes
        guard panel.runModal() == .OK else { return }
        let created = importFiles(panel.urls, into: folder)
        open(created)
    }

    /// Importiert die Dateien; Fehler werden gesammelt und am Ende in einem Hinweis gezeigt.
    @discardableResult
    static func importFiles(_ urls: [URL], into folder: URL, showErrors: Bool = true) -> [URL] {
        var created: [URL] = []
        var problems: [String] = []
        for url in urls {
            do {
                created.append(try importFile(url, into: folder))
            } catch {
                problems.append(L("„%@“: %@", url.lastPathComponent, error.localizedDescription))
            }
        }
        if showErrors && !problems.isEmpty {
            let alert = NSAlert()
            alert.messageText = problems.count == 1 ? L("Eine Datei ließ sich nicht importieren") : L("Einige Dateien ließen sich nicht importieren")
            alert.informativeText = problems.joined(separator: "\n")
            alert.runModal()
        }
        return created
    }

    static func importFile(_ url: URL, into folder: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        // Ein MindMaps-Dokument braucht keine Umwandlung: Es wird in die Bibliothek kopiert.
        if url.pathExtension.lowercased() == LibraryScanner.documentExtension {
            try LibraryStore.ensureLibrary(at: folder)
            return try LibraryStore.copy(url, to: folder)
        }
        let data = try MindMapImporter.importFile(at: url)
        try LibraryStore.ensureLibrary(at: folder)
        return try LibraryStore.createDocument(data, named: documentName(for: url), in: folder)
    }

    /// Dateiname ohne Endung; Zeichen, die in der Bibliothek nicht erlaubt sind, werden ersetzt.
    nonisolated static func documentName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? L("Import") : name
    }

    static func open(_ urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    /// Bibliotheksordner aus den Einstellungen.
    static var libraryRoot: URL {
        LibraryStore.libraryURL(fromStoredPath: UserDefaults.standard.string(forKey: "libraryPath") ?? "")
    }
}
