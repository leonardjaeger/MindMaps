import Foundation

/// Was Spotlight von einem Dokument erfährt (M9): Titel, alle Knotentexte und Notizen, Tags.
/// So findet die Systemsuche ein Dokument auch über ein Wort, das nur in einem Knoten steht.
struct SpotlightContent: Equatable {
    let title: String
    /// Alle Knotentexte, Notizen und Formeln in Lesereihenfolge (eine Zeile pro Eintrag).
    let text: String
    /// Kurzbeschreibung unter dem Treffer: Hauptknoten und Hauptäste.
    let summary: String
    /// Tags und der Text des Hauptknotens.
    let keywords: [String]

    static func make(title: String, data: MindMapDocumentData) -> SpotlightContent {
        var lines: [String] = []
        var tags: [String] = []
        func visit(_ node: Node) {
            for part in [node.text, node.note, node.formula] {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
            for tag in node.tags where !tags.contains(tag) { tags.append(tag) }
            node.children.forEach(visit)
        }
        visit(data.root)

        let root = data.root.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let branches = data.root.children
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var summary = root
        if !branches.isEmpty {
            summary += (summary.isEmpty ? "" : ": ") + branches.prefix(6).joined(separator: " · ")
            if branches.count > 6 { summary += " …" }
        }
        let keywords = (root.isEmpty ? [] : [root]) + tags
        return SpotlightContent(title: title, text: lines.joined(separator: "\n"),
                                summary: summary, keywords: keywords)
    }
}

/// Liest und ändert `.mindmaps`-Pakete direkt auf der Platte – für Kurzbefehle,
/// wenn das Dokument gerade nicht geöffnet ist (M9). Bilder und Vorschau bleiben unberührt.
enum MindMapPackage {
    enum PackageError: LocalizedError, Equatable {
        case notFound(String)
        case emptyText

        var errorDescription: String? {
            switch self {
            case .notFound(let name): return L("Das Dokument „%@“ wurde nicht gefunden.", name)
            case .emptyText: return L("Der Knoten braucht einen Text.")
            }
        }
    }

    static func documentURL(in package: URL) -> URL {
        package.appendingPathComponent(MindMapCodec.documentFileName)
    }

    static func read(_ package: URL) throws -> MindMapDocumentData {
        let json = documentURL(in: package)
        guard FileManager.default.fileExists(atPath: json.path) else {
            throw PackageError.notFound(package.deletingPathExtension().lastPathComponent)
        }
        return try MindMapCodec.decode(Data(contentsOf: json))
    }

    /// Schreibt nur `document.json` neu (atomar) und setzt das Änderungsdatum.
    static func write(_ data: MindMapDocumentData, to package: URL) throws {
        var document = data
        document.modifiedAt = MindMapDocumentData.now()
        try MindMapCodec.encode(document).write(to: documentURL(in: package), options: .atomic)
    }

    /// Wo ein neuer Knoten landet: unter dem ersten Knoten mit diesem Text (ohne Groß-/Kleinschreibung),
    /// sonst unter dem Hauptknoten.
    static func parentID(named name: String?, in root: Node) -> UUID {
        let wanted = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return root.id }
        var found: UUID?
        func visit(_ node: Node) {
            guard found == nil else { return }
            if node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                found = node.id
                return
            }
            node.children.forEach(visit)
        }
        visit(root)
        return found ?? root.id
    }

    /// Hängt einen Knoten an (optional als offene Aufgabe) und liefert seine ID.
    @discardableResult
    static func addNode(_ text: String, asTask: Bool, under parentName: String?,
                        to data: inout MindMapDocumentData) throws -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PackageError.emptyText }
        let node = Node(text: trimmed, task: asTask ? .open : nil)
        let parent = parentID(named: parentName, in: data.root)
        data.root.addChild(node, to: parent)
        data.root.expandAncestors(of: node.id)
        return node.id
    }
}
