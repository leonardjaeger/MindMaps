import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Dateityp `.mindmaps` – ein Paket (Ordner) mit `document.json` und `assets/`.
    /// Muss zu `UTExportedTypeDeclarations` in Config/Info.plist passen.
    static let mindMapsDocument = UTType(exportedAs: "de.leonardjaeger.mindmaps.document",
                                         conformingTo: .package)
}

/// Ein geöffnetes MindMaps-Dokument (Neu, Öffnen, Sichern, Versionen über das Ablage-Menü).
///
/// Seit M2 eine Klasse (`ReferenceFileDocument`): Jede Änderung läuft über `apply` und wird
/// dort als eigener Schritt für Rückgängig/Wiederholen registriert.
/// Seit M7 hält sie auch die Bilder (`assets/`) im Speicher.
final class MindMapFile: ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.mindMapsDocument] }

    @Published private(set) var data: MindMapDocumentData
    /// Bilddateien des Pakets (Name → Inhalt). Neue Bilder kommen hier hinzu;
    /// gesichert werden nur die, auf die ein Knoten verweist.
    @Published private(set) var assets: [String: Data]
    /// Verlauf: Zwischenstände im Ordner `Verlauf/` des Pakets (seit M10).
    @Published private(set) var history: HistoryStore
    /// Stand beim Öffnen – kommt beim ersten Sichern in den Verlauf, falls er dort noch fehlt.
    private var openedState: MindMapDocumentData?

    init(data: MindMapDocumentData = .newDocument(), assets: [String: Data] = [:],
         history: HistoryStore = HistoryStore()) {
        self.data = data
        self.assets = assets
        self.history = history
    }

    required init(configuration: ReadConfiguration) throws {
        let package = try Self.readPackage(configuration.file)
        data = package.data
        assets = package.assets
        history = Self.readHistory(configuration.file)
        openedState = package.data
    }

    /// Was gesichert wird: der Inhalt, die Bilder und (seit M4) ein Vorschaubild für Quick Look.
    struct Snapshot {
        var data: MindMapDocumentData
        var assets: [String: Data]
        var previewPNG: Data?
        var history = HistoryStore()
    }

    static let quickLookFolderName = "QuickLook"

    func snapshot(contentType: UTType) throws -> Snapshot {
        // Das Vorschaubild wird mit SwiftUI gezeichnet – das geht nur auf dem Hauptthread.
        let current = data
        let images = assets
        var preview: Data?
        if Thread.isMainThread {
            preview = MainActor.assumeIsolated { PreviewImage.png(for: current, assets: images) }
            // Verlauf (M10): beim Sichern höchstens alle 10 Minuten ein Zwischenstand.
            recordHistory()
        }
        return Snapshot(data: current, assets: images, previewPNG: preview, history: history)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let previewData = snapshot.previewPNG
            ?? configuration.existingFile?.fileWrappers?[Self.quickLookFolderName]?
                .fileWrappers?["Preview.png"]?.regularFileContents
        var document = snapshot.data
        document.modifiedAt = MindMapDocumentData.now()
        return try Self.makePackage(document, assets: snapshot.assets, preview: previewData, history: snapshot.history)
    }

    // MARK: - Paket lesen und schreiben (auch für Tests)

    static func readPackage(_ wrapper: FileWrapper) throws -> (data: MindMapDocumentData, assets: [String: Data]) {
        guard wrapper.isDirectory,
              let json = wrapper.fileWrappers?[MindMapCodec.documentFileName]?.regularFileContents
        else {
            throw MindMapCodec.CodecError.missingDocumentJSON
        }
        let data = try MindMapCodec.decode(json)
        var assets: [String: Data] = [:]
        for (name, file) in wrapper.fileWrappers?[MindMapCodec.assetsFolderName]?.fileWrappers ?? [:] {
            if let contents = file.regularFileContents { assets[name] = contents }
        }
        return (data, assets)
    }

    /// Baut das Paket. Alle FileWrapper werden neu angelegt: Ein FileWrapper kann nur in einem
    /// Ordner hängen, sonst stürzt macOS beim Sichern ab (Fehler aus M1, trat beim Beenden auf).
    static func makePackage(_ document: MindMapDocumentData, assets: [String: Data], preview: Data?,
                            history: HistoryStore = HistoryStore()) throws -> FileWrapper {
        let json = FileWrapper(regularFileWithContents: try MindMapCodec.encode(document))
        json.preferredFilename = MindMapCodec.documentFileName

        var assetFiles: [String: FileWrapper] = [:]
        // Auch Bilder, auf die nur noch der Verlauf verweist, bleiben (M10).
        for name in document.root.referencedAssets.union(history.assets) {
            guard let contents = assets[name] else { continue }
            let file = FileWrapper(regularFileWithContents: contents)
            file.preferredFilename = name
            assetFiles[name] = file
        }
        let assetFolder = FileWrapper(directoryWithFileWrappers: assetFiles)
        assetFolder.preferredFilename = MindMapCodec.assetsFolderName

        var files: [String: FileWrapper] = [
            MindMapCodec.documentFileName: json,
            MindMapCodec.assetsFolderName: assetFolder,
        ]

        // Vorschaubild für Quick Look (Leertaste im Finder).
        if let preview {
            let large = FileWrapper(regularFileWithContents: preview)
            large.preferredFilename = "Preview.png"
            let thumbnail = FileWrapper(regularFileWithContents: preview)
            thumbnail.preferredFilename = "Thumbnail.png"
            let quickLook = FileWrapper(directoryWithFileWrappers: ["Preview.png": large, "Thumbnail.png": thumbnail])
            quickLook.preferredFilename = quickLookFolderName
            files[quickLookFolderName] = quickLook
        }

        // Verlauf (M10): index.json und ein komprimierter Zwischenstand pro Datei.
        if !history.entries.isEmpty {
            var historyFiles: [String: FileWrapper] = [:]
            let index = FileWrapper(regularFileWithContents: try DocumentHistory.encodeIndex(history.entries))
            index.preferredFilename = DocumentHistory.indexFileName
            historyFiles[DocumentHistory.indexFileName] = index
            for entry in history.entries {
                guard let contents = history.files[entry.file] else { continue }
                let file = FileWrapper(regularFileWithContents: contents)
                file.preferredFilename = entry.file
                historyFiles[entry.file] = file
            }
            let folder = FileWrapper(directoryWithFileWrappers: historyFiles)
            folder.preferredFilename = DocumentHistory.folderName
            files[DocumentHistory.folderName] = folder
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }

    // MARK: - Verlauf (M10)

    /// Liest den Verlauf aus dem Paket (fehlt er, ist er leer).
    static func readHistory(_ wrapper: FileWrapper) -> HistoryStore {
        guard let folder = wrapper.fileWrappers?[DocumentHistory.folderName]?.fileWrappers,
              let index = folder[DocumentHistory.indexFileName]?.regularFileContents else { return HistoryStore() }
        var store = HistoryStore()
        for entry in DocumentHistory.decodeIndex(index) {
            guard let contents = folder[entry.file]?.regularFileContents else { continue }
            store.entries.append(entry)
            store.files[entry.file] = contents
        }
        return store
    }

    /// Nimmt einen Zwischenstand auf, wenn es Zeit dafür ist, und dünnt den Verlauf aus.
    /// Beim ersten Aufruf nach dem Öffnen kommt zuerst der geöffnete Stand dazu, falls er fehlt.
    func recordHistory(now: Date = Date()) {
        var store = history
        if let opened = openedState {
            openedState = nil
            let fingerprint = DocumentHistory.fingerprint(of: opened)
            let last = store.entries.max { $0.date < $1.date }
            if last?.fingerprint != fingerprint, opened.modifiedAt > (last?.date ?? .distantPast), opened.modifiedAt <= now {
                Self.add(opened, at: opened.modifiedAt, fingerprint: fingerprint, to: &store)
            }
        }
        let fingerprint = DocumentHistory.fingerprint(of: data)
        if DocumentHistory.shouldRecord(fingerprint: fingerprint, at: now, after: store.entries) {
            Self.add(data, at: now, fingerprint: fingerprint, to: &store)
        }
        let kept = DocumentHistory.thinned(store.entries, now: now)
        let names = Set(kept.map(\.file))
        store.entries = kept
        store.files = store.files.filter { names.contains($0.key) }
        if store != history { history = store }
    }

    private static func add(_ document: MindMapDocumentData, at time: Date, fingerprint: String,
                            to store: inout HistoryStore) {
        guard let json = try? MindMapCodec.encode(document) else { return }
        // Auf ganze Sekunden: So steht der Zeitpunkt nach dem Sichern (index.json, ISO 8601) genau gleich da.
        let date = Date(timeIntervalSince1970: time.timeIntervalSince1970.rounded(.down))
        var name = DocumentHistory.baseName(for: date) + ".json.lzfse"
        var number = 2
        while store.files[name] != nil {
            name = DocumentHistory.baseName(for: date) + "-\(number).json.lzfse"
            number += 1
        }
        store.files[name] = HistoryStore.compress(json)
        store.entries.insert(HistoryEntry(file: name, date: date, nodeCount: document.root.nodeCount,
                                          fingerprint: fingerprint,
                                          assets: document.root.referencedAssets.sorted()), at: 0)
        store.entries.sort { $0.date > $1.date }
    }

    /// Inhalt eines Zwischenstands.
    func historyDocument(_ entry: HistoryEntry) -> MindMapDocumentData? {
        history.document(entry)
    }

    // MARK: - Bilder

    /// Legt ein Bild im Paket ab und liefert seinen Dateinamen. Bleibt beim Rückgängigmachen erhalten.
    @discardableResult
    func addAsset(_ contents: Data, fileExtension: String) -> String {
        let name = UUID().uuidString.lowercased() + "." + fileExtension
        assets[name] = contents
        return name
    }

    // MARK: - Ändern mit Rückgängig/Wiederholen

    /// Ändert das Dokument und registriert die Änderung als einen Schritt zum Rückgängigmachen.
    /// Ändert sich nichts, wird auch nichts registriert.
    func apply(_ actionName: String, undoManager: UndoManager?,
               _ change: (inout MindMapDocumentData) -> Void) {
        var new = data
        change(&new)
        guard new != data else { return }
        replace(with: new, actionName: actionName, undoManager: undoManager)
    }

    /// Setzt einen neuen Stand und registriert den alten zum Zurückholen.
    /// Beim Rückgängigmachen ruft sich die Funktion selbst auf – so entsteht automatisch der Wiederholen-Schritt.
    private func replace(with new: MindMapDocumentData, actionName: String, undoManager: UndoManager?) {
        let old = data
        data = new
        undoManager?.registerUndo(withTarget: self) { document in
            document.replace(with: old, actionName: actionName, undoManager: undoManager)
        }
        // „Rückgängig: …“ im Menü – in der Sprache der Oberfläche (M12).
        undoManager?.setActionName(L(actionName))
    }
}

/// Verlauf eines Dokuments im Speicher (M10): Liste der Zwischenstände und ihr komprimierter Inhalt.
struct HistoryStore: Equatable {
    /// Neueste zuerst.
    var entries: [HistoryEntry] = []
    /// Dateiname → komprimiertes JSON.
    var files: [String: Data] = [:]

    /// Bilder, auf die ein Zwischenstand verweist.
    var assets: Set<String> { Set(entries.flatMap(\.assets)) }

    /// Größe des Verlaufs in Bytes (für Tests und die Anzeige).
    var byteCount: Int { files.values.reduce(0) { $0 + $1.count } }

    func document(_ entry: HistoryEntry) -> MindMapDocumentData? {
        guard let stored = files[entry.file] else { return nil }
        let json = Self.decompress(stored) ?? stored
        return try? MindMapCodec.decode(json)
    }

    static func compress(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .lzfse) as Data) ?? data
    }

    static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .lzfse) as Data
    }
}
