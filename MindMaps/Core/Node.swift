import Foundation

/// Ein Knoten der Mindmap. Der ganze Baum hängt am Hauptknoten (`MindMapDocumentData.root`).
///
/// Dieser Typ nutzt nur Foundation, damit er ohne SwiftUI getestet werden kann.
struct Node: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var text: String
    var isCollapsed: Bool
    var children: [Node]
    /// Notiz als Markdown-Teilmenge: **fett**, *kursiv*, [Link](url), Listen mit „- “ und „1. “ (seit M6).
    var note: String
    /// Namen der Tags, z. B. „Wichtig“. Farben stehen im Tag-Katalog der App (seit M6).
    var tags: [String]
    /// Aufgabe: offen oder erledigt; `nil` = keine Aufgabe (seit M6).
    var task: TaskMark?
    /// Web-Link oder Link auf einen anderen Knoten (`mindmaps://…`), leer = keiner (seit M7).
    var link: String
    /// Bild aus dem Ordner `assets/` des Dokuments (seit M7).
    var image: NodeImage?
    /// Formel in LaTeX-Schreibweise, z. B. `F = G \frac{m_1 m_2}{r^2}` (seit M7).
    var formula: String
    /// Eigener Stil: Form, Farben, Schrift, Zweigfarbe (seit M8).
    var style: NodeStyle?
    /// Von Hand verschoben: Abstand zur berechneten Position (seit M8).
    var offset: NodeOffset?

    init(id: UUID = UUID(), text: String, isCollapsed: Bool = false, children: [Node] = [],
         note: String = "", tags: [String] = [], task: TaskMark? = nil,
         link: String = "", image: NodeImage? = nil, formula: String = "",
         style: NodeStyle? = nil, offset: NodeOffset? = nil) {
        self.id = id
        self.text = text
        self.isCollapsed = isCollapsed
        self.children = children
        self.note = note
        self.tags = tags
        self.task = task
        self.link = link
        self.image = image
        self.formula = formula
        self.style = style
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, isCollapsed, children, note, tags, task, link, image, formula, style, offset
    }

    /// Fehlende Felder bekommen Standardwerte. So bleiben ältere Dateien lesbar,
    /// wenn neue Felder (Notiz, Tags, Aufgabe …) hinzukommen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        children = try c.decodeIfPresent([Node].self, forKey: .children) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        task = try? c.decodeIfPresent(TaskMark.self, forKey: .task)
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
        image = try? c.decodeIfPresent(NodeImage.self, forKey: .image)
        formula = try c.decodeIfPresent(String.self, forKey: .formula) ?? ""
        style = (try? c.decodeIfPresent(NodeStyle.self, forKey: .style)).flatMap { $0.isEmpty ? nil : $0 }
        offset = try? c.decodeIfPresent(NodeOffset.self, forKey: .offset)
    }

    /// Leere Felder werden weggelassen – Dateien ohne Notizen, Tags und Aufgaben sehen aus wie vor M6.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        if isCollapsed { try c.encode(isCollapsed, forKey: .isCollapsed) }
        if !children.isEmpty { try c.encode(children, forKey: .children) }
        if !note.isEmpty { try c.encode(note, forKey: .note) }
        if !tags.isEmpty { try c.encode(tags, forKey: .tags) }
        if let task { try c.encode(task, forKey: .task) }
        if !link.isEmpty { try c.encode(link, forKey: .link) }
        if let image { try c.encode(image, forKey: .image) }
        if !formula.isEmpty { try c.encode(formula, forKey: .formula) }
        if let style, !style.isEmpty { try c.encode(style, forKey: .style) }
        if let offset, !offset.isZero { try c.encode(offset, forKey: .offset) }
    }
}

/// Bild an einem Knoten: Datei im Ordner `assets/` und angezeigte Größe in Punkten.
struct NodeImage: Codable, Equatable, Hashable {
    var asset: String
    var width: Double
    var height: Double

    static let minWidth: Double = 40
    static let maxWidth: Double = 600

    /// Gleiches Seitenverhältnis, neue Breite (in erlaubten Grenzen).
    func resized(toWidth newWidth: Double) -> NodeImage {
        let w = min(max(newWidth, Self.minWidth), Self.maxWidth)
        let ratio = width > 0 ? height / width : 1
        return NodeImage(asset: asset, width: w.rounded(), height: (w * ratio).rounded())
    }
}

/// Querverbindung (Pfeil) von einem Knoten zu einem anderen (M7).
/// Sie hängt an den IDs – beim Umhängen eines Knotens bleibt sie also erhalten.
struct Connection: Codable, Equatable, Hashable, Identifiable {
    var id: UUID
    var from: UUID
    var to: UUID
    var label: String
    /// Verschiebung des Kurven-Griffs gegenüber der Mitte der geraden Linie (`nil` = Standardbogen).
    var bendX: Double?
    var bendY: Double?

    init(id: UUID = UUID(), from: UUID, to: UUID, label: String = "", bendX: Double? = nil, bendY: Double? = nil) {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
        self.bendX = bendX
        self.bendY = bendY
    }
}

/// Zustand einer Aufgabe.
enum TaskMark: String, Codable, Equatable, Hashable {
    case open, done
}
