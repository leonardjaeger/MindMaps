import Foundation

/// Formate, in die MindMaps exportieren kann.
enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown, opml, plainText, rtf, textBundle, freeMind
    case png, pdf, svg

    var id: String { rawValue }

    static let textFormats: [ExportFormat] = [.markdown, .opml, .plainText, .rtf, .textBundle, .freeMind]
    static let imageFormats: [ExportFormat] = [.png, .pdf, .svg]

    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .opml: return "OPML"
        case .plainText: return L("Klartext")
        case .rtf: return L("RTF (Word, Pages, TextEdit)")
        case .textBundle: return "TextBundle"
        case .freeMind: return "FreeMind"
        case .png: return L("PNG-Bild")
        case .pdf: return "PDF"
        case .svg: return "SVG"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .opml: return "opml"
        case .plainText: return "txt"
        case .rtf: return "rtf"
        case .textBundle: return "textbundle"
        case .freeMind: return "mm"
        case .png: return "png"
        case .pdf: return "pdf"
        case .svg: return "svg"
        }
    }

    var isImage: Bool { Self.imageFormats.contains(self) }

    /// Kurze Erklärung im Export-Dialog.
    var explanation: String {
        switch self {
        case .markdown:
            return L("Hauptknoten als Überschrift, Hauptäste als Zwischenüberschriften, alles darunter als eingerückte Liste.")
        case .opml:
            return L("Gliederung für andere Mindmap- und Outline-Programme (z. B. MindNode, OmniOutliner, Workflowy).")
        case .plainText:
            return L("Ein Knoten pro Zeile, Unterknoten mit Tabulator eingerückt.")
        case .rtf:
            return L("Formatierter Text mit Überschriften und Aufzählung – öffnet sich in Word, Pages und TextEdit.")
        case .textBundle:
            return L("Markdown-Paket für Schreib-Apps wie Ulysses oder Bear.")
        case .freeMind:
            return L("Mindmap-Datei für FreeMind, Freeplane und viele andere Mindmap-Programme.")
        case .png:
            return L("Bild der Mindmap, so wie sie in der Map zu sehen ist.")
        case .pdf:
            return L("Gestochen scharf (Vektorgrafik) – auf eine Seite oder auf A4-Seiten verteilt.")
        case .svg:
            return L("Vektorgrafik für Browser, Keynote, Illustrator und Inkscape.")
        }
    }
}

/// Dateien, die MindMaps einlesen kann, und das Einlesen selbst.
enum MindMapImporter {
    enum ImportError: LocalizedError, Equatable {
        case unsupported(String)
        case unreadable(String)
        case empty

        var errorDescription: String? {
            switch self {
            case .unsupported(let ext):
                return L("Dateien mit der Endung „.%@“ kann MindMaps nicht importieren.", ext)
            case .unreadable(let reason):
                return L("Die Datei ließ sich nicht lesen: %@", reason)
            case .empty:
                return L("In der Datei steht nichts, woraus sich eine Mindmap machen ließe.")
            }
        }
    }

    enum Kind: CaseIterable {
        case markdown, plainText, opml, freeMind, textBundle

        var fileExtensions: [String] {
            switch self {
            case .markdown: return ["md", "markdown", "mdown", "mkd"]
            case .plainText: return ["txt", "text"]
            case .opml: return ["opml"]
            case .freeMind: return ["mm"]
            case .textBundle: return ["textbundle"]
            }
        }
    }

    static var supportedExtensions: [String] { Kind.allCases.flatMap(\.fileExtensions) }

    static func kind(for url: URL) -> Kind? {
        let ext = url.pathExtension.lowercased()
        return Kind.allCases.first { $0.fileExtensions.contains(ext) }
    }

    static func canImport(_ url: URL) -> Bool { kind(for: url) != nil }

    /// Liest eine Datei und macht daraus ein Dokument (Thema: Standard).
    static func importFile(at url: URL) throws -> MindMapDocumentData {
        guard let kind = kind(for: url) else { throw ImportError.unsupported(url.pathExtension) }
        let title = url.deletingPathExtension().lastPathComponent
        let root: Node
        switch kind {
        case .markdown:
            root = try MarkdownFormat.parse(readText(url), fallbackTitle: title)
        case .plainText:
            root = try PlainTextFormat.parse(readText(url), fallbackTitle: title)
        case .opml:
            root = try OPMLFormat.parse(readData(url), fallbackTitle: title)
        case .freeMind:
            root = try FreeMindFormat.parse(readData(url), fallbackTitle: title)
        case .textBundle:
            root = try MarkdownFormat.parse(TextBundleFormat.markdownText(in: url), fallbackTitle: title)
        }
        return MindMapDocumentData(root: root)
    }

    static func readData(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
    }

    /// Text als UTF-8, sonst UTF-16 bzw. Windows-/Mac-Zeichensatz (ältere Dateien).
    static func readText(_ url: URL) throws -> String {
        try decodeText(readData(url))
    }

    static func decodeText(_ data: Data) throws -> String {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data(data.dropFirst(3)) : data
        for encoding in [String.Encoding.utf8, .windowsCP1252, .macOSRoman] {
            if let text = String(data: bytes, encoding: encoding) { return text }
        }
        throw ImportError.unreadable(L("unbekannte Zeichenkodierung"))
    }
}

/// Hilfsbaum zum Aufbauen beim Einlesen (Klasse, damit Eltern ihre Kinder direkt ergänzen können).
final class OutlineBuilder {
    var text: String
    var isCollapsed = false
    var children: [OutlineBuilder] = []
    var note = ""
    var task: TaskMark?

    init(_ text: String) { self.text = text }

    @discardableResult
    func add(_ text: String) -> OutlineBuilder {
        let child = OutlineBuilder(text)
        children.append(child)
        return child
    }

    var node: Node {
        Node(text: text, isCollapsed: isCollapsed && !children.isEmpty, children: children.map(\.node),
             note: note, task: task)
    }

    /// Hat die Hülle genau ein Kind, wird dieses zum Hauptknoten; sonst trägt die Hülle den Dateinamen.
    static func finish(_ top: OutlineBuilder) throws -> Node {
        if top.children.isEmpty { throw MindMapImporter.ImportError.empty }
        if top.children.count == 1 { return top.children[0].node }
        return top.node
    }
}

/// XML-Hilfen für OPML, FreeMind und SVG.
enum XMLText {
    /// Für Text und Attributwerte in doppelten Anführungszeichen; Zeilenumbrüche bleiben als &#10; erhalten.
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "\n": out += "&#10;"
            case "\r": break
            case "\t": out += "&#9;"
            default:
                // Steuerzeichen sind in XML nicht erlaubt.
                if scalar.value < 0x20 { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
