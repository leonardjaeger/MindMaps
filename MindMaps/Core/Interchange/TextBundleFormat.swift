import Foundation

/// TextBundle (textbundle.org): Ordnerpaket mit `text.markdown` und `info.json`.
enum TextBundleFormat {
    static let textFileName = "text.markdown"

    static func fileWrapper(for root: Node) -> FileWrapper {
        let info: [String: Any] = [
            "version": 2,
            "type": "net.daringfireball.markdown",
            "transient": false,
            "creatorIdentifier": "de.leonardjaeger.MindMaps",
        ]
        let infoData = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let bundle = FileWrapper(directoryWithFileWrappers: [:])
        bundle.addRegularFile(withContents: infoData, preferredFilename: "info.json")
        bundle.addRegularFile(withContents: Data(MarkdownFormat.export(root).utf8), preferredFilename: textFileName)
        let assets = FileWrapper(directoryWithFileWrappers: [:])
        assets.preferredFilename = "assets"
        bundle.addFileWrapper(assets)
        return bundle
    }

    /// Markdown-Text aus einem TextBundle-Ordner (`text.markdown`, `text.md` o. Ä.).
    static func markdownText(in url: URL) throws -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        guard let name = names.first(where: { $0 == textFileName })
                ?? names.first(where: { $0.hasPrefix("text.") }) else {
            throw MindMapImporter.ImportError.unreadable(L("im TextBundle fehlt die Textdatei"))
        }
        return try MindMapImporter.readText(url.appendingPathComponent(name))
    }
}
