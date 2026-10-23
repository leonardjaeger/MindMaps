import Foundation

/// Datei-Aktionen der Bibliothek: Ordner, Dokumente anlegen, verschieben, umbenennen,
/// eigener Papierkorb mit Wiederherstellen. Nur Foundation, damit alles getestet werden kann.
enum LibraryStore {
    enum LibraryError: LocalizedError, Equatable {
        case invalidName
        case nameTaken(String)
        case moveIntoItself

        var errorDescription: String? {
            switch self {
            case .invalidName:
                return L("Der Name darf nicht leer sein und keinen Schrägstrich (/) oder Doppelpunkt (:) enthalten.")
            case .nameTaken(let name):
                return L("„%@“ gibt es an diesem Ort schon.", name)
            case .moveIntoItself:
                return L("Ein Ordner kann nicht in sich selbst verschoben werden.")
            }
        }
    }

    static let trashFolderName = ".Papierkorb"
    private static let originsFileName = ".herkunft.json"
    private static var fileManager: FileManager { .default }

    // MARK: - Bibliothek

    /// Standardordner: ~/Documents/MindMaps (in den Einstellungen änderbar).
    static var defaultLibraryURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindMaps", isDirectory: true)
    }

    static func libraryURL(fromStoredPath path: String) -> URL {
        path.isEmpty ? defaultLibraryURL : URL(fileURLWithPath: path, isDirectory: true)
    }

    static func ensureLibrary(at root: URL) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    static func trashURL(for root: URL) -> URL {
        root.appendingPathComponent(trashFolderName, isDirectory: true)
    }

    // MARK: - Namen

    /// Freier Name im Ordner: „Name“, „Name 2“, „Name 3“ …
    static func uniqueURL(named base: String, pathExtension: String?, in folder: URL) -> URL {
        func candidate(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name)
            if let pathExtension, !pathExtension.isEmpty { return url.appendingPathExtension(pathExtension) }
            return url
        }
        var url = candidate(base)
        var number = 2
        while fileManager.fileExists(atPath: url.path) {
            url = candidate("\(base) \(number)")
            number += 1
        }
        return url
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix(".") && !trimmed.contains("/") && !trimmed.contains(":")
    }

    // MARK: - Anlegen

    @discardableResult
    static func createFolder(named name: String = L("Neuer Ordner"), in folder: URL) throws -> URL {
        guard isValidName(name) else { throw LibraryError.invalidName }
        let url = uniqueURL(named: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            pathExtension: nil, in: folder)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Schreibt ein neues `.mindmaps`-Paket (document.json + assets/).
    @discardableResult
    static func createDocument(_ data: MindMapDocumentData, named name: String, in folder: URL) throws -> URL {
        guard isValidName(name) else { throw LibraryError.invalidName }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = uniqueURL(named: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            pathExtension: LibraryScanner.documentExtension, in: folder)
        try fileManager.createDirectory(at: url.appendingPathComponent(MindMapCodec.assetsFolderName),
                                        withIntermediateDirectories: true)
        try MindMapCodec.encode(data).write(to: url.appendingPathComponent(MindMapCodec.documentFileName))
        return url
    }

    // MARK: - Verschieben und Umbenennen

    /// Verschiebt Dokument oder Ordner nach `folder`. Liegt es schon dort, passiert nichts.
    @discardableResult
    static func move(_ item: URL, to folder: URL) throws -> URL {
        let itemPath = item.resolvingSymlinksInPath().standardizedFileURL.path
        let folderPath = folder.resolvingSymlinksInPath().standardizedFileURL.path
        if item.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == folderPath {
            return item
        }
        if folderPath == itemPath || folderPath.hasPrefix(itemPath + "/") {
            throw LibraryError.moveIntoItself
        }
        let target = uniqueURL(named: item.deletingPathExtension().lastPathComponent,
                               pathExtension: item.pathExtension, in: folder)
        try fileManager.moveItem(at: item, to: target)
        return target
    }

    /// Kopiert ein Dokument von außerhalb (z. B. aus dem Finder hineingezogen) in die Bibliothek.
    @discardableResult
    static func copy(_ item: URL, to folder: URL) throws -> URL {
        let target = uniqueURL(named: item.deletingPathExtension().lastPathComponent,
                               pathExtension: item.pathExtension, in: folder)
        try fileManager.copyItem(at: item, to: target)
        return target
    }

    /// Benennt um. Bei Dokumenten bleibt die Endung `.mindmaps` erhalten.
    @discardableResult
    static func rename(_ item: URL, to newName: String) throws -> URL {
        guard isValidName(newName) else { throw LibraryError.invalidName }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var target = item.deletingLastPathComponent().appendingPathComponent(trimmed)
        if !item.pathExtension.isEmpty { target.appendPathExtension(item.pathExtension) }
        if target.standardizedFileURL == item.standardizedFileURL { return item }
        // Nur Groß-/Kleinschreibung geändert: auf dem Mac dieselbe Datei – über einen Zwischennamen.
        if target.path.lowercased() == item.path.lowercased() {
            let temporary = item.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try fileManager.moveItem(at: item, to: temporary)
            try fileManager.moveItem(at: temporary, to: target)
            return target
        }
        guard !fileManager.fileExists(atPath: target.path) else { throw LibraryError.nameTaken(trimmed) }
        try fileManager.moveItem(at: item, to: target)
        return target
    }

    // MARK: - Papierkorb der Bibliothek

    /// Legt ein Dokument oder einen Ordner in den Papierkorb der Bibliothek und merkt sich die Herkunft.
    @discardableResult
    static func moveToTrash(_ item: URL, libraryRoot root: URL) throws -> URL {
        let trash = trashURL(for: root)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let target = uniqueURL(named: item.deletingPathExtension().lastPathComponent,
                               pathExtension: item.pathExtension, in: trash)
        let origin = relativePath(of: item.deletingLastPathComponent(), in: root)
        try fileManager.moveItem(at: item, to: target)
        var origins = readOrigins(root)
        origins[target.lastPathComponent] = origin
        try writeOrigins(origins, root)
        return target
    }

    /// Holt einen Eintrag aus dem Papierkorb an seinen alten Ort zurück
    /// (fehlt der Ordner inzwischen, wird er neu angelegt).
    @discardableResult
    static func restore(_ trashed: URL, libraryRoot root: URL) throws -> URL {
        var origins = readOrigins(root)
        let origin = origins[trashed.lastPathComponent] ?? ""
        let folder = origin.isEmpty ? root : root.appendingPathComponent(origin, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = uniqueURL(named: trashed.deletingPathExtension().lastPathComponent,
                               pathExtension: trashed.pathExtension, in: folder)
        try fileManager.moveItem(at: trashed, to: target)
        origins[trashed.lastPathComponent] = nil
        try writeOrigins(origins, root)
        return target
    }

    /// Endgültig aus der Bibliothek entfernen – landet im Papierkorb von macOS (dort noch rettbar).
    static func deletePermanently(_ trashed: URL, libraryRoot root: URL) throws {
        try fileManager.trashItem(at: trashed, resultingItemURL: nil)
        var origins = readOrigins(root)
        origins[trashed.lastPathComponent] = nil
        try writeOrigins(origins, root)
    }

    static func emptyTrash(libraryRoot root: URL) throws {
        for item in LibraryScanner.contents(of: trashURL(for: root)) {
            try fileManager.trashItem(at: item, resultingItemURL: nil)
        }
        try writeOrigins([:], root)
    }

    static func readOrigins(_ root: URL) -> [String: String] {
        let url = trashURL(for: root).appendingPathComponent(originsFileName)
        guard let data = try? Data(contentsOf: url),
              let origins = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return origins
    }

    private static func writeOrigins(_ origins: [String: String], _ root: URL) throws {
        let trash = trashURL(for: root)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(origins).write(to: trash.appendingPathComponent(originsFileName))
    }

    /// Pfad von `url` relativ zu `root` ("" für `root` selbst).
    static func relativePath(of url: URL, in root: URL) -> String {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(base) else { return "" }
        return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
