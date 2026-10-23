import SwiftUI
import AppKit

extension Color {
    init(rgba: RGBAColor) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }

    /// Farbe aus "#RRGGBB"; ungültige Werte werden grau.
    init(hex: String) {
        self.init(rgba: RGBAColor(hex: hex) ?? RGBAColor(red: 0.5, green: 0.5, blue: 0.5))
    }
}

/// Schriften, Abstände und Größen der Knoten – abhängig von Thema, Ebene und eigenem Stil (M8).
struct NodeMetrics {
    let theme: Theme
    /// Layout und Zweige der Map (M8).
    var style = MapStyle()

    init(theme: Theme, style: MapStyle = MapStyle()) {
        self.theme = theme
        self.style = style
    }

    static let maxTextWidth: CGFloat = 220

    // MARK: Schrift

    func fontSize(depth: Int) -> CGFloat {
        switch depth {
        case 0: return 17
        case 1: return 14
        default: return 13
        }
    }

    func fontSize(for node: Node, depth: Int) -> CGFloat {
        node.style?.fontSize.map { CGFloat($0) } ?? fontSize(depth: depth)
    }

    func weight(depth: Int) -> NSFont.Weight {
        if theme.font == .systemBold { return .bold }
        switch depth {
        case 0: return .semibold
        case 1: return .medium
        default: return .regular
        }
    }

    func weight(for node: Node, depth: Int) -> NSFont.Weight {
        if let bold = node.style?.bold { return bold ? .bold : .regular }
        if node.style?.font == .systemBold { return .bold }
        if let font = node.style?.font, font != .systemBold, theme.font == .systemBold {
            return depth == 0 ? .semibold : (depth == 1 ? .medium : .regular)
        }
        return weight(depth: depth)
    }

    func isItalic(_ node: Node) -> Bool { node.style?.italic ?? false }

    func fontFamily(for node: Node) -> Theme.Font { node.style?.font ?? theme.font }

    /// Form des Knotens (eigene Form oder die des Themas).
    func shape(of node: Node, depth: Int) -> Theme.NodeShape {
        NodeAppearance.shape(of: node, depth: depth, theme: theme)
    }

    func padding(depth: Int) -> CGSize {
        switch depth {
        case 0: return CGSize(width: 18, height: 10)
        case 1: return CGSize(width: 12, height: 6)
        default: return CGSize(width: 10, height: 5)
        }
    }

    /// Innenabstand; Linie und Eingebettet brauchen wenig Rand.
    func padding(depth: Int, shape: Theme.NodeShape) -> CGSize {
        switch shape {
        case .line: return CGSize(width: 4, height: 4)
        case .embedded: return CGSize(width: 6, height: 4)
        default: return padding(depth: depth)
        }
    }

    func nsFont(depth: Int) -> NSFont {
        nsFont(size: fontSize(depth: depth), weight: weight(depth: depth), family: theme.font, italic: false)
    }

    func nsFont(for node: Node, depth: Int) -> NSFont {
        nsFont(size: fontSize(for: node, depth: depth), weight: weight(for: node, depth: depth),
               family: fontFamily(for: node), italic: isItalic(node))
    }

    private func nsFont(size: CGFloat, weight: NSFont.Weight, family: Theme.Font, italic: Bool) -> NSFont {
        var font: NSFont
        switch family {
        case .monospaced:
            font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded, .serif:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let design: NSFontDescriptor.SystemDesign = family == .rounded ? .rounded : .serif
            font = base.fontDescriptor.withDesign(design).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .system, .systemBold:
            font = NSFont.systemFont(ofSize: size, weight: weight)
        }
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        return font
    }

    private static func swiftUIWeight(_ weight: NSFont.Weight) -> Font.Weight {
        switch weight {
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        default: return .regular
        }
    }

    private static func design(_ family: Theme.Font) -> Font.Design {
        switch family {
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        case .system, .systemBold: return .default
        }
    }

    /// `scale` vergrößert die Schrift mit dem Zoom (für das Textfeld beim Bearbeiten in der Map).
    func font(depth: Int, scale: CGFloat = 1) -> Font {
        .system(size: fontSize(depth: depth) * scale, weight: Self.swiftUIWeight(weight(depth: depth)),
                design: Self.design(theme.font))
    }

    func font(for node: Node, depth: Int, scale: CGFloat = 1) -> Font {
        let font = Font.system(size: fontSize(for: node, depth: depth) * scale,
                               weight: Self.swiftUIWeight(weight(for: node, depth: depth)),
                               design: Self.design(fontFamily(for: node)))
        return isItalic(node) ? font.italic() : font
    }

    /// Anzeigetext; leere Knoten bekommen einen Platzhalter.
    static func displayText(_ node: Node) -> String {
        node.text.isEmpty ? "…" : node.text
    }

    func textSize(of node: Node, depth: Int) -> CGSize {
        let string = Self.displayText(node)
        let key = TextSizeCache.Key(text: string, size: fontSize(for: node, depth: depth),
                                    weight: weight(for: node, depth: depth).rawValue,
                                    family: fontFamily(for: node), italic: isItalic(node))
        return TextSizeCache.shared.size(for: key) {
            let text = NSAttributedString(string: string, attributes: [.font: nsFont(for: node, depth: depth)])
            let rect = text.boundingRect(with: CGSize(width: Self.maxTextWidth, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         context: nil)
            return CGSize(width: ceil(rect.width), height: ceil(rect.height))
        }
    }

    // MARK: Größe und Aufteilung

    /// Größe des Inhalts (Bild, Textzeile, Formel, Tags) ohne Rand.
    func contentSize(of node: Node, depth: Int) -> CGSize {
        contentSize(contentBlocks(node, decor: NodeDecor(node), depth: depth))
    }

    private func contentSize(_ blocks: [Block]) -> CGSize {
        let width = blocks.map(\.size.width).max() ?? 0
        let height = blocks.reduce(0) { $0 + $1.size.height } + gaps(blocks)
        return CGSize(width: width, height: max(height, 12))
    }

    func size(of node: Node, depth: Int) -> CGSize {
        let shape = self.shape(of: node, depth: depth)
        return ShapeGeometry.frameSize(shape, content: contentSize(of: node, depth: depth),
                                       padding: padding(depth: depth, shape: shape))
    }

    /// Bestandteile eines Knotens von oben nach unten (M7): Bild, Textzeile, Formel, Tags.
    private enum BlockKind { case image, row, formula, tags }
    private struct Block {
        let kind: BlockKind
        let size: CGSize
    }

    private func contentBlocks(_ node: Node, decor: NodeDecor, depth: Int) -> [Block] {
        var blocks: [Block] = []
        if let image = decor.image {
            blocks.append(Block(kind: .image, size: CGSize(width: image.width, height: image.height)))
        }
        let text = decor.showsText ? textSize(of: node, depth: depth) : .zero
        if decor.showsText || decor.hasIcons {
            blocks.append(Block(kind: .row, size: CGSize(
                width: decor.leadingWidth + text.width + decor.trailingWidth,
                height: max(text.height, decor.hasIcons ? NodeDecor.iconSize : 0))))
        }
        if let formula = decor.formula {
            blocks.append(Block(kind: .formula, size: CGSize(width: formula.width, height: formula.height)))
        }
        if !decor.tags.isEmpty {
            blocks.append(Block(kind: .tags, size: decor.tagsSize))
        }
        return blocks
    }

    private func gaps(_ blocks: [Block]) -> CGFloat {
        guard blocks.count > 1 else { return 0 }
        return zip(blocks, blocks.dropFirst()).reduce(0) { sum, pair in
            sum + (pair.1.kind == .tags ? NodeDecor.tagGap : NodeDecor.blockGap)
        }
    }

    /// Wo im Knoten Bild, Kästchen, Text, Symbole, Formel und Tags sitzen.
    func contentLayout(of node: Node, depth: Int, frame: CGRect) -> NodeContentLayout {
        let decor = NodeDecor(node)
        let icon = NodeDecor.iconSize
        let blocks = contentBlocks(node, decor: decor, depth: depth)
        // Der Inhalt sitzt mittig im Knoten – bei Kreis, Wolke, Sechseck … bleibt so rundum Platz.
        let content = contentSize(blocks)
        var inner = CGRect(x: frame.midX - content.width / 2, y: frame.midY - content.height / 2,
                           width: content.width, height: content.height)
        if shape(of: node, depth: depth) == .line {
            // Linie: Text steht direkt über der Linie am unteren Rand.
            inner.origin.y = frame.maxY - padding(depth: depth, shape: .line).height - content.height
        }

        var layout = NodeContentLayout(decor: decor, textRect: .zero)
        var y = inner.minY
        for (index, block) in blocks.enumerated() {
            if index > 0 { y += block.kind == .tags ? NodeDecor.tagGap : NodeDecor.blockGap }
            switch block.kind {
            case .image:
                layout.imageRect = CGRect(x: inner.midX - block.size.width / 2, y: y,
                                          width: block.size.width, height: block.size.height)
            case .row:
                let height = block.size.height
                let iconY = y + (height - icon) / 2
                if decor.leading != nil {
                    layout.leadingRect = CGRect(x: inner.minX, y: iconY, width: icon, height: icon)
                }
                var trailingX = inner.maxX
                if decor.hasNote {
                    layout.noteRect = CGRect(x: trailingX - icon, y: iconY, width: icon, height: icon)
                    trailingX -= icon + NodeDecor.iconGap
                }
                if decor.hasLink {
                    layout.linkRect = CGRect(x: trailingX - icon, y: iconY, width: icon, height: icon)
                }
                if decor.showsText {
                    layout.textRect = CGRect(x: inner.minX + decor.leadingWidth, y: y,
                                             width: max(inner.width - decor.leadingWidth - decor.trailingWidth, 1),
                                             height: height)
                }
            case .formula:
                if let box = decor.formula {
                    layout.formulaRect = CGRect(x: inner.midX - box.width / 2, y: y, width: box.width, height: box.height)
                }
            case .tags:
                var x = inner.minX
                for tag in decor.tags {
                    let width = NodeDecor.tagWidth(tag)
                    layout.tagRects.append((tag, CGRect(x: x, y: y, width: width, height: NodeDecor.tagHeight)))
                    x += width + NodeDecor.tagSpacing
                }
            }
            y += block.size.height
        }
        return layout
    }

    // MARK: Zweige

    var branchStyle: Theme.BranchStyle { style.effectiveBranchStyle(theme) }
    var branchWidthMode: Theme.BranchWidth { style.effectiveBranchWidth(theme) }

    /// Breite (bei „Verjüngt“: am Ende) des Zweigs, der in einen Knoten der Ebene `depth` führt.
    func branchWidth(depth: Int) -> CGFloat {
        branchWidths(childDepth: depth).end
    }

    /// Breite am Anfang und am Ende eines Zweigs. „Verjüngt“ wird entlang des Zweigs gleichmäßig dünner.
    func branchWidths(childDepth depth: Int) -> (start: CGFloat, end: CGFloat) {
        let factor = CGFloat(style.branchThickness)
        switch branchWidthMode {
        case .tapered:
            let steps: [CGFloat] = [7, 4, 2.5, 1.6]
            let start = steps[min(max(depth - 1, 0), steps.count - 1)]
            let end = steps[min(max(depth, 0), steps.count - 1)]
            return (start * factor, end * factor)
        case .uniform: return (2.5 * factor, 2.5 * factor)
        case .uniformThick: return (4 * factor, 4 * factor)
        }
    }

    /// Stärke der Linie unter Knoten mit der Form „Linie“.
    func underlineWidth(depth: Int) -> CGFloat {
        max(1.5, branchWidths(childDepth: depth).end * 0.8)
    }
}

/// Was außer dem Text im Knoten steht: Kästchen bzw. Fortschritt, Notiz-Symbol, Tags (M6).
struct NodeDecor: Equatable {
    enum Leading: Equatable {
        /// Aufgabe (auch mit Unteraufgaben: dann zeigt das Kästchen deren Stand).
        case checkbox(TaskStatus)
        /// Keine Aufgabe, aber Aufgaben darunter: Fortschrittskreis.
        case progress(done: Int, total: Int)
    }

    var leading: Leading?
    var hasNote: Bool
    var tags: [String]
    var hasLink: Bool
    var image: NodeImage?
    /// Gesetzte Formel (M7)
    var formula: MathBox?
    /// Text zeigen? Leere Knoten mit Bild oder Formel brauchen keinen Platzhalter.
    var showsText: Bool

    static let iconSize: CGFloat = 14
    static let iconGap: CGFloat = 6
    static let tagHeight: CGFloat = 15
    static let tagGap: CGFloat = 4
    static let tagSpacing: CGFloat = 4
    static let tagFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    static let blockGap: CGFloat = 6

    init(_ node: Node) {
        if node.task != nil, let status = node.taskStatus {
            leading = .checkbox(status)
        } else if node.hasTaskDescendants {
            let progress = node.taskProgress
            leading = .progress(done: progress.done, total: progress.total)
        }
        hasNote = !node.note.isEmpty
        tags = node.tags
        hasLink = !node.link.isEmpty
        image = node.image
        let source = node.formula.trimmingCharacters(in: .whitespacesAndNewlines)
        formula = source.isEmpty ? nil : MathTypesetter.layout(source)
        showsText = !node.text.isEmpty || (node.image == nil && source.isEmpty)
    }

    var hasIcons: Bool { leading != nil || hasNote || hasLink }
    var leadingWidth: CGFloat { leading == nil ? 0 : Self.iconSize + Self.iconGap }
    var trailingWidth: CGFloat {
        (hasNote ? Self.iconGap + Self.iconSize : 0) + (hasLink ? Self.iconGap + Self.iconSize : 0)
    }

    static func tagWidth(_ tag: String) -> CGFloat {
        TextSizeCache.shared.size(for: TextSizeCache.Key(text: tag, size: -9, weight: 0, family: .system, italic: false)) {
            let width = (tag as NSString).size(withAttributes: [.font: tagFont]).width
            return CGSize(width: ceil(width) + 12, height: tagHeight)
        }.width
    }

    var tagsSize: CGSize {
        guard !tags.isEmpty else { return .zero }
        let width = tags.map(Self.tagWidth).reduce(0, +) + CGFloat(tags.count - 1) * Self.tagSpacing
        return CGSize(width: width, height: Self.tagHeight)
    }
}

/// Positionen der Bestandteile eines Knotens (Map-Koordinaten).
struct NodeContentLayout {
    var decor: NodeDecor
    var textRect: CGRect
    var leadingRect: CGRect?
    var noteRect: CGRect?
    var linkRect: CGRect?
    var imageRect: CGRect?
    var formulaRect: CGRect?
    var tagRects: [(tag: String, rect: CGRect)] = []

    /// Grundlinie der Formel.
    var formulaOrigin: CGPoint? {
        guard let rect = formulaRect, let box = decor.formula else { return nil }
        return CGPoint(x: rect.minX, y: rect.minY + box.ascent)
    }
}

/// Gemessene Textgrößen (M12). Layout und Zeichnen fragen dieselben Texte immer wieder an –
/// bei großen Maps (1.000 Knoten) war das Messen der größte Zeitfresser.
final class TextSizeCache: @unchecked Sendable {
    static let shared = TextSizeCache()

    struct Key: Hashable {
        let text: String
        let size: CGFloat
        let weight: CGFloat
        let family: Theme.Font
        let italic: Bool
    }

    private let lock = NSLock()
    private var sizes: [Key: CGSize] = [:]
    private let limit = 20_000

    /// Alles vergessen (Tests: Messung „kalt“ starten).
    func removeAll() {
        lock.lock()
        sizes.removeAll()
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return sizes.count
    }

    func size(for key: Key, measure: () -> CGSize) -> CGSize {
        lock.lock()
        if let known = sizes[key] {
            lock.unlock()
            return known
        }
        lock.unlock()
        let measured = measure()
        lock.lock()
        if sizes.count >= limit { sizes.removeAll(keepingCapacity: true) }
        sizes[key] = measured
        lock.unlock()
        return measured
    }
}
