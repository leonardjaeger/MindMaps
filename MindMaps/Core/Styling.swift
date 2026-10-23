import Foundation

// MARK: - Stil eines Knotens (M8)

/// Eigener Stil eines Knotens. Nur gesetzte Werte überschreiben das Thema –
/// `nil` heißt „wie im Thema“. Leere Stile werden nicht gespeichert.
struct NodeStyle: Codable, Equatable, Hashable {
    var shape: Theme.NodeShape?
    /// Hintergrund (Füllfarbe) als Hex-Wert.
    var fill: String?
    /// Rahmenfarbe.
    var border: String?
    /// Rahmenstärke in Punkten; 0 = kein Rahmen.
    var borderWidth: Double?
    var textColor: String?
    var font: Theme.Font?
    var fontSize: Double?
    var bold: Bool?
    var italic: Bool?
    /// Zweigfarbe: gilt für den Zweig zu diesem Knoten und für alle Unterknoten.
    var branchColor: String?

    init(shape: Theme.NodeShape? = nil, fill: String? = nil, border: String? = nil, borderWidth: Double? = nil,
         textColor: String? = nil, font: Theme.Font? = nil, fontSize: Double? = nil,
         bold: Bool? = nil, italic: Bool? = nil, branchColor: String? = nil) {
        self.shape = shape
        self.fill = fill
        self.border = border
        self.borderWidth = borderWidth
        self.textColor = textColor
        self.font = font
        self.fontSize = fontSize
        self.bold = bold
        self.italic = italic
        self.branchColor = branchColor
    }

    private enum CodingKeys: String, CodingKey {
        case shape, fill, border, borderWidth, textColor, font, fontSize, bold, italic, branchColor
    }

    /// Unbekannte Werte (z. B. eine Form aus einer neueren Version) werden einzeln übergangen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = try? c.decodeIfPresent(Theme.NodeShape.self, forKey: .shape)
        fill = try? c.decodeIfPresent(String.self, forKey: .fill)
        border = try? c.decodeIfPresent(String.self, forKey: .border)
        borderWidth = try? c.decodeIfPresent(Double.self, forKey: .borderWidth)
        textColor = try? c.decodeIfPresent(String.self, forKey: .textColor)
        font = try? c.decodeIfPresent(Theme.Font.self, forKey: .font)
        fontSize = try? c.decodeIfPresent(Double.self, forKey: .fontSize)
        bold = try? c.decodeIfPresent(Bool.self, forKey: .bold)
        italic = try? c.decodeIfPresent(Bool.self, forKey: .italic)
        branchColor = try? c.decodeIfPresent(String.self, forKey: .branchColor)
    }

    var isEmpty: Bool { self == NodeStyle() }

    /// Erlaubte Schriftgrößen im Inspektor.
    static let fontSizes: ClosedRange<Double> = 9...40
    static let borderWidths: ClosedRange<Double> = 0...6
}

/// Von Hand verschobener Knoten: Abstand zur berechneten Position (Unterknoten wandern mit).
struct NodeOffset: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    var isZero: Bool { x == 0 && y == 0 }
}

extension Node {
    /// Alle von Hand gesetzten Positionen entfernen (Layout wechseln, „Positionen zurücksetzen“).
    mutating func clearOffsets() {
        offset = nil
        for index in children.indices { children[index].clearOffsets() }
    }

    /// Zahl der von Hand verschobenen Knoten.
    var movedNodeCount: Int {
        (offset == nil ? 0 : 1) + children.reduce(0) { $0 + $1.movedNodeCount }
    }

    /// Zahl der Knoten mit eigenem Stil.
    var styledNodeCount: Int {
        (style == nil ? 0 : 1) + children.reduce(0) { $0 + $1.styledNodeCount }
    }

    /// Ebene und Zweigfarbe eines Knotens – wie in der Map (eigene bzw. geerbte Zweigfarbe,
    /// sonst die Farbe seines Hauptasts).
    func styleContext(of id: UUID, palette: ThemePalette) -> (depth: Int, branchHex: String)? {
        guard let path = path(to: id) else { return nil }
        var branchIndex = 0
        var inherited: String?
        var current = self
        for (level, nodeID) in path.enumerated() {
            if level > 0, let next = current.children.firstIndex(where: { $0.id == nodeID }) {
                if level == 1 { branchIndex = next }
                current = current.children[next]
            }
            if let color = current.style?.branchColor { inherited = color }
        }
        return (path.count - 1, inherited ?? palette.branchColor(at: branchIndex))
    }
}

// MARK: - Stil der ganzen Map (M8)

/// Layout und Zweige einer Mindmap. `nil` bei Zweigstil und -breite heißt „wie im Thema“.
struct MapStyle: Codable, Equatable {
    enum Layout: String, Codable, CaseIterable, Identifiable {
        case horizontal, vertical, compact, radial
        var id: String { rawValue }
    }

    /// Ausrichtung der Hauptäste: beidseitig, nur nach rechts/unten, nur nach links/oben.
    enum Sides: String, Codable, CaseIterable, Identifiable {
        case both, primary, secondary
        var id: String { rawValue }
    }

    var layout: Layout = .horizontal
    var sides: Sides = .both
    var branchStyle: Theme.BranchStyle?
    var branchWidth: Theme.BranchWidth?
    /// Faktor für die Zweigstärke (0,5 … 2).
    var branchThickness: Double = 1
    /// Faktor für den Abstand zwischen den Ebenen (0,5 … 2,5).
    var levelSpacing: Double = 1
    /// Faktor für den Abstand zwischen Geschwisterknoten (0,5 … 3).
    var siblingSpacing: Double = 1

    static let thicknessRange: ClosedRange<Double> = 0.5...2
    static let levelSpacingRange: ClosedRange<Double> = 0.5...2.5
    static let siblingSpacingRange: ClosedRange<Double> = 0.5...3

    init(layout: Layout = .horizontal, sides: Sides = .both) {
        self.layout = layout
        self.sides = sides
    }

    private enum CodingKeys: String, CodingKey {
        case layout, sides, branchStyle, branchWidth, branchThickness, levelSpacing, siblingSpacing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = (try? c.decodeIfPresent(Layout.self, forKey: .layout)) ?? .horizontal
        sides = (try? c.decodeIfPresent(Sides.self, forKey: .sides)) ?? .both
        branchStyle = try? c.decodeIfPresent(Theme.BranchStyle.self, forKey: .branchStyle)
        branchWidth = try? c.decodeIfPresent(Theme.BranchWidth.self, forKey: .branchWidth)
        branchThickness = (try? c.decodeIfPresent(Double.self, forKey: .branchThickness)) ?? 1
        levelSpacing = (try? c.decodeIfPresent(Double.self, forKey: .levelSpacing)) ?? 1
        siblingSpacing = (try? c.decodeIfPresent(Double.self, forKey: .siblingSpacing)) ?? 1
    }

    var isDefault: Bool { self == MapStyle() }

    /// Übliche Ausrichtung eines Layouts (vertikal: nur nach unten).
    static func defaultSides(for layout: Layout) -> Sides {
        layout == .vertical ? .primary : .both
    }

    func effectiveBranchStyle(_ theme: Theme) -> Theme.BranchStyle { branchStyle ?? theme.branchStyle }
    func effectiveBranchWidth(_ theme: Theme) -> Theme.BranchWidth { branchWidth ?? theme.branchWidth }
}

// MARK: - Aufgelöstes Aussehen eines Knotens

/// Farben und Form eines Knotens, nachdem Thema, Zweigfarbe und eigener Stil zusammengeführt sind.
/// Map, SVG-Export und Druck benutzen dieselbe Auflösung – so sieht alles gleich aus.
struct NodeAppearance: Equatable {
    var shape: Theme.NodeShape
    /// Füllung; `nil` = keine (Linie, Eingebettet).
    var fill: String?
    /// Rahmen; `nil` = keiner.
    var border: String?
    var borderWidth: Double
    var text: String
    /// Farbe für Kästchen, Link-Symbol usw.
    var accent: String
    /// Farbe des Zweigs, der in diesen Knoten führt (Hauptknoten: erste Zweigfarbe).
    var branch: String

    /// Hat die Form eine Fläche (alles außer Linie und Eingebettet)?
    var isBoxed: Bool { shape != .line && shape != .embedded }

    /// Form eines Knotens: eigene Form, sonst die des Themas (der Hauptknoten hat immer eine Fläche,
    /// außer man wählt für ihn selbst „Linie“ oder „Eingebettet“).
    static func shape(of node: Node, depth: Int, theme: Theme) -> Theme.NodeShape {
        if let shape = node.style?.shape { return shape }
        if depth == 0 && (theme.nodeShape == .line || theme.nodeShape == .embedded) { return .rounded }
        return theme.nodeShape
    }

    static func resolve(_ node: Node, depth: Int, branchHex: String, theme: Theme,
                        palette: ThemePalette) -> NodeAppearance {
        let style = node.style ?? NodeStyle()
        let isRoot = depth == 0
        let shape = Self.shape(of: node, depth: depth, theme: theme)
        let boxed = shape != .line && shape != .embedded

        var fill: String?
        var border: String?
        var borderWidth: Double = 0
        if isRoot {
            fill = boxed ? palette.rootFill : nil
        } else if boxed {
            if theme.nodeFill == .tinted,
               let base = RGBAColor(hex: palette.nodeFill), let tint = RGBAColor(hex: branchHex) {
                fill = base.mixed(with: tint, amount: depth == 1 ? 0.22 : 0.12).hexString
            } else {
                fill = palette.nodeFill
                border = branchHex
                borderWidth = theme.branchWidth == .uniformThick ? 2.5 : 1.5
            }
        }
        if let custom = style.fill { fill = custom }
        if let custom = style.border {
            border = custom
            if borderWidth == 0 { borderWidth = 1.5 }
        }
        if let width = style.borderWidth {
            borderWidth = width
            if border == nil && width > 0 { border = branchHex }
        }
        if borderWidth <= 0 { border = nil; borderWidth = 0 }

        // Auf der Fläche des Hauptknotens steht der Text in der Hauptknoten-Textfarbe –
        // mit eigenem Hintergrund in der normalen Textfarbe.
        let onRootFill = isRoot && boxed && style.fill == nil
        let text = style.textColor ?? (onRootFill ? palette.rootText : palette.nodeText)
        let accent = onRootFill ? palette.rootText : branchHex
        return NodeAppearance(shape: shape, fill: fill, border: border, borderWidth: borderWidth,
                              text: text, accent: accent, branch: branchHex)
    }
}

extension RGBAColor {
    /// "#RRGGBB" bzw. "#RRGGBBAA" bei Transparenz.
    var hexString: String {
        func byte(_ v: Double) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
        if alpha >= 0.999 {
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }
        return String(format: "#%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }
}

// MARK: - Namen für die Oberfläche

extension Theme.NodeShape {
    var title: String {
        switch self {
        case .circle: return L("Kreis")
        case .square: return L("Quadrat")
        case .rectangle: return L("Rechteck")
        case .rounded: return L("Abgerundet")
        case .pill: return L("Pill")
        case .cloud: return L("Wolke")
        case .line: return L("Linie")
        case .embedded: return L("Eingebettet")
        case .hexagon: return L("Sechseck")
        case .octagon: return L("Achteck")
        }
    }
}

extension Theme.Font {
    var title: String {
        switch self {
        case .system: return L("System")
        case .rounded: return L("Gerundet")
        case .serif: return L("Serifen")
        case .systemBold: return L("System fett")
        case .monospaced: return L("Schreibmaschine")
        }
    }
}

extension Theme.BranchStyle {
    var title: String {
        switch self {
        case .curved: return L("Geschwungen")
        case .angled: return L("Eckig")
        }
    }
}

extension Theme.BranchWidth {
    var title: String {
        switch self {
        case .uniform: return L("Gleichmäßig")
        case .uniformThick: return L("Kräftig")
        case .tapered: return L("Verjüngt")
        }
    }
}

extension Theme.NodeFillMode {
    var title: String {
        switch self {
        case .plain: return L("Rahmen in Zweigfarbe")
        case .tinted: return L("Getönte Fläche")
        }
    }
}

extension MapStyle.Layout {
    var title: String {
        switch self {
        case .horizontal: return L("Horizontal")
        case .vertical: return L("Vertikal")
        case .compact: return L("Kompakt")
        case .radial: return L("Radial")
        }
    }

    var symbol: String {
        switch self {
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.down"
        case .compact: return "list.bullet.indent"
        case .radial: return "circle.circle"
        }
    }

    /// Hat das Layout eine Einstellung „Ausrichtung“?
    var hasSides: Bool { self == .horizontal || self == .vertical }
}

extension MapStyle.Sides {
    func title(for layout: MapStyle.Layout) -> String {
        switch (self, layout) {
        case (.both, .vertical): return L("Oben und unten")
        case (.both, _): return L("Beidseitig")
        case (.primary, .vertical): return L("Nach unten")
        case (.primary, _): return L("Nur rechts")
        case (.secondary, .vertical): return L("Nach oben")
        case (.secondary, _): return L("Nur links")
        }
    }
}
