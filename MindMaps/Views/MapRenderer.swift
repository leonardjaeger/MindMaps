import SwiftUI

/// Zeichnet die Mindmap in Map-Koordinaten (Zoom und Verschiebung setzt der Aufrufer vorher).
struct MapRenderer {
    let root: Node
    let layout: MindMapLayout
    let theme: Theme
    let palette: ThemePalette
    let metrics: NodeMetrics
    /// Farben der Tags (Katalog der App).
    var tagCatalog: TagCatalog = TagStore.catalog
    /// Bilder des Dokuments (M7).
    var images: AssetImages = .empty
    /// Querverbindungen (M7).
    var connections: [Connection] = []
    /// Alle Knoten nach ID – schneller als jedes Mal im Baum zu suchen.
    private let models: [UUID: Node]
    /// Aussehen, Aufteilung und Zweige pro Knoten – einmal berechnet, bei jedem Bild wiederverwendet (M12).
    /// Beim Verschieben und Zoomen wird so nur noch gezeichnet, nicht neu vermessen.
    private let cache = DrawCache()

    private final class DrawCache {
        var looks: [UUID: NodeAppearance] = [:]
        var contents: [UUID: NodeContentLayout] = [:]
        var branches: [UUID: BranchDrawing] = [:]
        var noBranch: Set<UUID> = []
    }

    init(root: Node, layout: MindMapLayout, theme: Theme, palette: ThemePalette, metrics: NodeMetrics,
         tagCatalog: TagCatalog = TagStore.catalog, images: AssetImages = .empty, connections: [Connection] = []) {
        self.root = root
        self.layout = layout
        self.theme = theme
        self.palette = palette
        self.metrics = metrics
        self.tagCatalog = tagCatalog
        self.images = images
        self.connections = connections
        var models: [UUID: Node] = [:]
        func index(_ node: Node) {
            models[node.id] = node
            node.children.forEach(index)
        }
        index(root)
        self.models = models
    }

    func model(_ id: UUID) -> Node? { models[id] }

    /// Was gerade hervorgehoben werden soll.
    struct State {
        var selection: UUID?
        var editing: UUID?
        var dragging: UUID?
        var dragOffset: CGSize = .zero
        var dropTarget: UUID?
        var showHandle = true
        /// Blass gezeichnete Knoten (Hervorheben-Modus: alles andere tritt zurück).
        var dimmed: Set<UUID> = []
        /// Suchtreffer (gelb umrandet) und der aktuelle Treffer (kräftiger).
        var matches: Set<UUID> = []
        var currentMatch: UUID?
        /// Nicht gezeichnete Knoten (Präsentation: noch nicht aufgedeckt).
        var hidden: Set<UUID> = []
        var selectedConnection: UUID?
        /// Verbindung, die gerade mit ⌥ gezogen wird: von Knoten zu Punkt (ggf. Zielknoten).
        var connectionDraft: (from: UUID, to: CGPoint, target: UUID?)?
        /// Sichtbarer Ausschnitt (Map-Koordinaten): Was außerhalb liegt, wird nicht gezeichnet (M12).
        /// `nil` = alles (Export, Druck, Vorschaubild).
        var visibleRect: CGRect?
        /// Zoom der Ansicht. Unter `greekingZoom` ist Text ohnehin unlesbar klein –
        /// dann stehen schlichte Balken an seiner Stelle, das zeichnet viel schneller (M12).
        var zoom: CGFloat = 1
    }

    static let greekingZoom: CGFloat = 0.3

    /// Liegt `rect` (mit Rand für Griffe, Zähler und Schatten) im sichtbaren Ausschnitt?
    private static func isVisible(_ rect: CGRect, in visible: CGRect?, margin: CGFloat = 40) -> Bool {
        guard let visible else { return true }
        return rect.insetBy(dx: -margin, dy: -margin).intersects(visible)
    }

    /// Positionen von Kästchen, Text, Notiz-Symbol und Tags eines Knotens.
    func contentLayout(for placed: LayoutNode) -> NodeContentLayout? {
        if let known = cache.contents[placed.id] { return known }
        guard let model = models[placed.id] else { return nil }
        let content = metrics.contentLayout(of: model, depth: placed.depth, frame: placed.frame)
        cache.contents[placed.id] = content
        return content
    }

    // MARK: - Aussehen (M8)

    /// Zweigfarbe eines Knotens: eigene bzw. geerbte, sonst die des Hauptasts.
    func branchHex(for placed: LayoutNode) -> String {
        placed.branchColor ?? palette.branchColor(at: max(placed.branchIndex, 0))
    }

    func appearance(for placed: LayoutNode) -> NodeAppearance? {
        if let known = cache.looks[placed.id] { return known }
        guard let model = models[placed.id] else { return nil }
        let look = NodeAppearance.resolve(model, depth: placed.depth, branchHex: branchHex(for: placed),
                                          theme: theme, palette: palette)
        cache.looks[placed.id] = look
        return look
    }

    /// Ein Zweig, fertig zum Zeichnen: Fläche (verjüngt) oder Linie mit fester Breite.
    struct BranchDrawing {
        let centerline: [PathElement]
        /// Gesetzt bei „Verjüngt“: Fläche statt Linie.
        let taperedOutline: [PathElement]?
        let width: CGFloat
        let color: String
    }

    func branch(to placed: LayoutNode) -> BranchDrawing? {
        if let known = cache.branches[placed.id] { return known }
        if cache.noBranch.contains(placed.id) { return nil }
        let drawing = makeBranch(to: placed)
        if let drawing { cache.branches[placed.id] = drawing } else { cache.noBranch.insert(placed.id) }
        return drawing
    }

    private func makeBranch(to placed: LayoutNode) -> BranchDrawing? {
        guard let pid = placed.parentID, let parent = layout.nodes[pid],
              let parentModel = models[pid], let childModel = models[placed.id] else { return nil }
        let parentShape = metrics.shape(of: parentModel, depth: parent.depth)
        let childShape = metrics.shape(of: childModel, depth: placed.depth)
        let boxedRoot = parent.depth == 0 && parentShape != .line && parentShape != .embedded
        let line = BranchGeometry.centerline(parent: parent, child: placed, kind: layout.kind,
                                             style: metrics.branchStyle, parentInset: boxedRoot ? 6 : 0,
                                             parentShape: parentShape, childShape: childShape)
        let widths = metrics.branchWidths(childDepth: placed.depth)
        let tapered = metrics.branchWidthMode == .tapered
            ? BranchGeometry.taperedOutline(line, startWidth: widths.start, endWidth: widths.end) : nil
        return BranchDrawing(centerline: line, taperedOutline: tapered, width: widths.end, color: branchHex(for: placed))
    }

    // MARK: - Griffe

    static let handleRadius: CGFloat = 9

    /// Radius des „+“ in Map-Koordinaten: 9, aber auf dem Bildschirm nie kleiner als 11 pt (höchstens dreifach).
    static func handleRadius(zoom: CGFloat) -> CGFloat {
        min(max(handleRadius, 11 / max(zoom, 0.01)), handleRadius * 3)
    }

    /// Der „+“-Griff sitzt außen neben dem Knoten, in Wachstumsrichtung (im vertikalen Layout rechts daneben).
    /// Bei Knoten mit Unterknoten sitzt davor der Einklapp-Knopf bzw. der Zähler, der Griff rückt nach außen.
    /// „+“ am ausgewählten Knoten. Auf dem Bildschirm mindestens 22 pt groß – auch weit herausgezoomt (1.1.2).
    func handleRect(for node: LayoutNode, zoom: CGFloat = 1) -> CGRect {
        let r = Self.handleRadius(zoom: zoom)
        let extra = r - Self.handleRadius
        var anchor = node
        let center: CGPoint
        if layout.kind == .vertical {
            anchor.growth = CGVector(dx: node.side == .left && node.depth > 0 ? -1 : 1, dy: 0)
            center = BranchGeometry.outwardPoint(of: anchor, distance: 16 + extra)
        } else {
            center = BranchGeometry.outwardPoint(of: anchor, distance: (hasFoldControl(node.id) ? 44 : 16) + extra)
        }
        return CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    }

    /// Hat der Knoten einen Einklapp-Knopf (−) bzw. Zähler? Alle Knoten mit Unterknoten außer dem Hauptknoten.
    func hasFoldControl(_ id: UUID) -> Bool {
        canToggleCollapse(id) || isCollapsed(id)
    }

    /// Wie `Node.canToggleCollapse`, aber ohne den Baum zu durchsuchen.
    private func canToggleCollapse(_ id: UUID) -> Bool {
        id != root.id && !(models[id]?.children.isEmpty ?? true)
    }

    /// Eingeklappt und mit verborgenen Unterknoten?
    func isCollapsed(_ id: UUID) -> Bool {
        guard let node = models[id] else { return false }
        return node.isCollapsed && !node.children.isEmpty
    }

    /// Kreis außen neben dem Knoten (in Wachstumsrichtung): Zahl der verborgenen Knoten (eingeklappt)
    /// oder Einklapp-Knopf „−“ (ausgewählt, aufgeklappt).
    func badgeRect(for node: LayoutNode) -> CGRect {
        let r: CGFloat = 10
        let center = BranchGeometry.outwardPoint(of: node, distance: 16)
        return CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    }

    func draw(in context: inout GraphicsContext, state: State) {
        drawBranches(in: &context, dimmed: state.dimmed, hidden: state.hidden, visible: state.visibleRect)
        drawConnections(in: &context, state: state)
        drawNodes(in: &context, state: state)
        drawOverlays(in: &context, state: state)
    }

    // MARK: - Querverbindungen (M7)

    struct ConnectionGeometry {
        let start: CGPoint
        let end: CGPoint
        let control: CGPoint
        /// Griff zum Biegen, liegt auf der Kurve (Mitte)
        let handle: CGPoint

        var path: Path {
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
            return path
        }

        /// Punkte entlang der Kurve (für Klicks).
        func samples(_ count: Int = 24) -> [CGPoint] {
            (0...count).map { i in
                let t = CGFloat(i) / CGFloat(count)
                let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
                return CGPoint(x: a * start.x + b * control.x + c * end.x,
                               y: a * start.y + b * control.y + c * end.y)
            }
        }
    }

    /// Standardbogen: seitlich versetzt, damit die Verbindung sich von den Zweigen abhebt.
    static func defaultBend(from a: CGPoint, to b: CGPoint) -> CGSize {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 1)
        let amount = min(70, length * 0.25)
        return CGSize(width: -dy / length * amount, height: dx / length * amount)
    }

    func geometry(for connection: Connection, override bend: CGSize? = nil) -> ConnectionGeometry? {
        guard let a = layout.nodes[connection.from]?.frame, let b = layout.nodes[connection.to]?.frame else { return nil }
        let p0 = CGPoint(x: a.midX, y: a.midY)
        let p2 = CGPoint(x: b.midX, y: b.midY)
        let mid = CGPoint(x: (p0.x + p2.x) / 2, y: (p0.y + p2.y) / 2)
        let offset = bend ?? connection.bendX.flatMap { x in connection.bendY.map { CGSize(width: x, height: $0) } }
            ?? Self.defaultBend(from: p0, to: p2)
        let handle = CGPoint(x: mid.x + offset.width, y: mid.y + offset.height)
        // Quadratische Kurve, die bei t = 0,5 durch den Griff läuft.
        let control = CGPoint(x: 2 * handle.x - mid.x, y: 2 * handle.y - mid.y)
        return ConnectionGeometry(start: Self.boundaryPoint(of: a, toward: control, margin: 4),
                                  end: Self.boundaryPoint(of: b, toward: control, margin: 6),
                                  control: control, handle: handle)
    }

    /// Punkt auf dem Rand von `rect` in Richtung `target` (vom Mittelpunkt aus).
    static func boundaryPoint(of rect: CGRect, toward target: CGPoint, margin: CGFloat) -> CGPoint {
        ShapeGeometry.boundaryPoint(of: rect, toward: target, margin: margin)
    }

    /// Verbindung unter einem Punkt (Griff oder Linie).
    func connection(at point: CGPoint, tolerance: CGFloat = 7) -> UUID? {
        for connection in connections.reversed() {
            guard let geometry = geometry(for: connection) else { continue }
            if hypot(geometry.handle.x - point.x, geometry.handle.y - point.y) < tolerance + 4 { return connection.id }
            if geometry.samples().contains(where: { hypot($0.x - point.x, $0.y - point.y) < tolerance }) {
                return connection.id
            }
        }
        return nil
    }

    var connectionColor: Color { Color(hex: palette.nodeText).opacity(0.6) }

    private func drawConnections(in context: inout GraphicsContext, state: State) {
        for connection in connections {
            guard !state.hidden.contains(connection.from), !state.hidden.contains(connection.to),
                  let geometry = geometry(for: connection) else { continue }
            var context = context
            if state.dimmed.contains(connection.from) && state.dimmed.contains(connection.to) {
                context.opacity = Self.dimmedOpacity
            }
            let selected = state.selectedConnection == connection.id
            let color = selected ? Color.accentColor : connectionColor
            context.stroke(geometry.path, with: .color(color),
                           style: StrokeStyle(lineWidth: selected ? 2.5 : 1.8, lineCap: .round, dash: [6, 4]))
            Self.drawArrowhead(in: &context, tip: geometry.end, from: geometry.control, color: color)
            if !connection.label.isEmpty {
                let label = Text(connection.label).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(hex: palette.nodeText))
                let resolved = context.resolve(label)
                let size = resolved.measure(in: CGSize(width: 200, height: 40))
                let box = CGRect(x: geometry.handle.x - size.width / 2 - 6, y: geometry.handle.y - size.height / 2 - 3,
                                 width: size.width + 12, height: size.height + 6)
                let capsule = Path(roundedRect: box, cornerRadius: box.height / 2, style: .continuous)
                context.fill(capsule, with: .color(Color(hex: palette.canvas)))
                context.stroke(capsule, with: .color(color), lineWidth: 1)
                context.draw(resolved, at: geometry.handle, anchor: .center)
            }
            if selected {
                let dot = CGRect(x: geometry.handle.x - 6, y: geometry.handle.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot), with: .color(.white))
                context.stroke(Path(ellipseIn: dot), with: .color(.accentColor), lineWidth: 2)
            }
        }
        // Vorschau beim Ziehen mit ⌥.
        if let draft = state.connectionDraft, let from = layout.nodes[draft.from]?.frame {
            let target = draft.target.flatMap { layout.nodes[$0]?.frame }
            let end = target.map { CGPoint(x: $0.midX, y: $0.midY) } ?? draft.to
            var path = Path()
            path.move(to: CGPoint(x: from.midX, y: from.midY))
            path.addLine(to: end)
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            if let target {
                let ring = Path(roundedRect: target.insetBy(dx: -6, dy: -6), cornerRadius: 10, style: .continuous)
                context.stroke(ring, with: .color(.accentColor), lineWidth: 2.5)
            }
        }
    }

    static func drawArrowhead(in context: inout GraphicsContext, tip: CGPoint, from: CGPoint, color: Color) {
        let dx = tip.x - from.x, dy = tip.y - from.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let size: CGFloat = 9
        var head = Path()
        head.move(to: tip)
        head.addLine(to: CGPoint(x: tip.x - ux * size - uy * size * 0.55, y: tip.y - uy * size + ux * size * 0.55))
        head.addLine(to: CGPoint(x: tip.x - ux * size + uy * size * 0.55, y: tip.y - uy * size - ux * size * 0.55))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    // MARK: - Zweige

    private func drawBranches(in context: inout GraphicsContext, dimmed: Set<UUID>, hidden: Set<UUID>,
                              visible: CGRect?) {
        for id in layout.order where !hidden.contains(id) {
            guard let node = layout.nodes[id], let parentID = node.parentID,
                  let parent = layout.nodes[parentID],
                  Self.isVisible(node.frame.union(parent.frame), in: visible),
                  let drawing = branch(to: node) else { continue }
            var context = context
            if dimmed.contains(id) { context.opacity = Self.dimmedOpacity }
            let color = Color(hex: drawing.color)
            if let outline = drawing.taperedOutline {
                context.fill(Path(elements: outline), with: .color(color))
            } else {
                context.stroke(Path(elements: drawing.centerline), with: .color(color),
                               style: StrokeStyle(lineWidth: drawing.width, lineCap: .round, lineJoin: .round))
            }
        }
    }

    static let dimmedOpacity: Double = 0.2

    private func drawNodes(in outer: inout GraphicsContext, state: State) {
        for id in layout.order where !state.hidden.contains(id) {
            guard let node = layout.nodes[id], let model = models[id],
                  Self.isVisible(node.frame, in: state.visibleRect) else { continue }
            var context = outer
            if state.dimmed.contains(id) { context.opacity = Self.dimmedOpacity }
            let isRoot = node.depth == 0
            let rect = node.frame
            guard let look = appearance(for: node) else { continue }

            // Form, Füllung, Rahmen (M8: 10 Formen, eigener Stil).
            let outline = ShapeGeometry.outline(look.shape, in: rect)
            if !outline.isEmpty {
                let path = Path(elements: outline)
                if let fill = look.fill { context.fill(path, with: .color(Color(hex: fill))) }
                if let border = look.border {
                    context.stroke(path, with: .color(Color(hex: border)), lineWidth: look.borderWidth)
                }
            } else if let fill = look.fill {
                // Linie/Eingebettet mit eigenem Hintergrund: sanft hinterlegen.
                context.fill(Path(roundedRect: rect, cornerRadius: 6, style: .continuous), with: .color(Color(hex: fill)))
            }
            if look.shape == .line {
                context.stroke(Path(elements: ShapeGeometry.underline(rect)), with: .color(Color(hex: look.branch)),
                               style: StrokeStyle(lineWidth: metrics.underlineWidth(depth: node.depth), lineCap: .round))
            }

            if state.matches.contains(id) {
                let current = state.currentMatch == id
                let ring = Path(roundedRect: rect.insetBy(dx: current ? -7 : -6, dy: current ? -7 : -6),
                                cornerRadius: 10, style: .continuous)
                context.stroke(ring, with: .color(current ? Color.orange : Color.yellow),
                               lineWidth: current ? 3.5 : 2.5)
            }

            if state.selection == id {
                let ring = Path(roundedRect: rect.insetBy(dx: -4, dy: -4), cornerRadius: 8, style: .continuous)
                context.stroke(ring, with: .color(.accentColor), lineWidth: 2.5)
            }

            if model.isCollapsed && !model.children.isEmpty {
                drawCollapsedBadge(in: &context, node: node, hiddenCount: model.nodeCount - 1,
                                   color: Color(hex: isRoot ? (look.fill ?? look.branch) : look.branch))
            }

            guard let content = contentLayout(for: node) else { continue }
            let textColor = Color(hex: look.text)
            let accent = Color(hex: look.accent)
            drawDecorations(in: &context, content: content, textColor: textColor, accent: accent)

            if let rect = content.imageRect, let image = model.image {
                drawImage(in: &context, asset: image.asset, rect: rect,
                          resizeHandle: state.selection == id && state.showHandle)
            }
            if let origin = content.formulaOrigin, let box = content.decor.formula {
                MathTypesetter.draw(box, in: &context, origin: origin, color: textColor)
            }

            // Beim Bearbeiten zeigt das Textfeld den Text.
            if state.editing == id || !content.decor.showsText { continue }

            if state.zoom < Self.greekingZoom {
                drawTextPlaceholder(in: &context, rect: content.textRect, color: textColor)
                continue
            }

            let text = Text(NodeMetrics.displayText(model))
                .font(metrics.font(for: model, depth: node.depth))
                .foregroundStyle(model.text.isEmpty ? textColor.opacity(0.5) : textColor)
            context.draw(text, in: content.textRect)
        }
    }

    /// Stark verkleinert: Balken statt Text (eine Zeile pro 18 Punkt Texthöhe).
    private func drawTextPlaceholder(in context: inout GraphicsContext, rect: CGRect, color: Color) {
        let lines = max(1, Int((rect.height / 18).rounded()))
        let lineHeight = rect.height / CGFloat(lines)
        var bars = Path()
        for line in 0..<lines {
            let width = line == lines - 1 && lines > 1 ? rect.width * 0.6 : rect.width
            bars.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + CGFloat(line) * lineHeight + lineHeight * 0.3,
                                           width: width, height: lineHeight * 0.4),
                                cornerSize: CGSize(width: 2, height: 2))
        }
        context.fill(bars, with: .color(color.opacity(0.45)))
    }

    // MARK: - Bilder (M7)

    static let resizeHandleSize: CGFloat = 12

    /// Griff zum Ändern der Bildgröße (unten rechts im Bild).
    static func resizeHandle(for imageRect: CGRect) -> CGRect {
        CGRect(x: imageRect.maxX - resizeHandleSize + 3, y: imageRect.maxY - resizeHandleSize + 3,
               width: resizeHandleSize, height: resizeHandleSize)
    }

    private func drawImage(in context: inout GraphicsContext, asset: String, rect: CGRect, resizeHandle: Bool) {
        let shape = Path(roundedRect: rect, cornerRadius: 6, style: .continuous)
        if let image = images.image(asset) {
            var clipped = context
            clipped.clip(to: shape)
            clipped.draw(Image(nsImage: image).resizable(), in: rect)
        } else {
            // Bild fehlt (z. B. Vorschau in der Bibliothek): Platzhalter.
            context.fill(shape, with: .color(Color.gray.opacity(0.18)))
            let symbol = context.resolve(Image(systemName: "photo"))
            let side = min(rect.width, rect.height) * 0.35
            context.draw(symbol, in: CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side))
        }
        if resizeHandle {
            let handle = Self.resizeHandle(for: rect)
            let box = Path(roundedRect: handle, cornerRadius: 3)
            context.fill(box, with: .color(.white))
            context.stroke(box, with: .color(.accentColor), lineWidth: 1.5)
        }
    }

    // MARK: - Kästchen, Fortschritt, Notiz-Symbol, Tags (M6)

    private func drawDecorations(in context: inout GraphicsContext, content: NodeContentLayout,
                                 textColor: Color, accent: Color) {
        if let rect = content.leadingRect, let leading = content.decor.leading {
            switch leading {
            case .checkbox(let status):
                Self.drawCheckbox(in: &context, rect: rect, status: status, color: accent, textColor: textColor)
            case .progress(let done, let total):
                Self.drawProgress(in: &context, rect: rect, done: done, total: total, color: accent, textColor: textColor)
            }
        }
        if let rect = content.noteRect {
            Self.drawNoteIcon(in: &context, rect: rect, color: textColor.opacity(0.65))
        }
        if let rect = content.linkRect {
            Self.drawLinkIcon(in: &context, rect: rect, color: accent)
        }
        for (tag, rect) in content.tagRects {
            let color = Color(hex: tagCatalog.hex(for: tag))
            context.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2, style: .continuous), with: .color(color))
            let label = Text(tag).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.white)
            context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }

    static func drawCheckbox(in context: inout GraphicsContext, rect: CGRect, status: TaskStatus,
                             color: Color, textColor: Color) {
        let box = Path(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 3.5, style: .continuous)
        switch status {
        case .open:
            context.stroke(box, with: .color(textColor.opacity(0.7)), lineWidth: 1.5)
        case .partial:
            context.stroke(box, with: .color(color), lineWidth: 1.5)
            var dash = Path()
            dash.move(to: CGPoint(x: rect.minX + 3.5, y: rect.midY))
            dash.addLine(to: CGPoint(x: rect.maxX - 3.5, y: rect.midY))
            context.stroke(dash, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case .done:
            context.fill(box, with: .color(color))
            var check = Path()
            check.move(to: CGPoint(x: rect.minX + 3.2, y: rect.midY + 0.3))
            check.addLine(to: CGPoint(x: rect.minX + 6, y: rect.maxY - 3.6))
            check.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY + 3.6))
            context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }

    static func drawProgress(in context: inout GraphicsContext, rect: CGRect, done: Int, total: Int,
                             color: Color, textColor: Color) {
        let circle = rect.insetBy(dx: 1, dy: 1)
        context.stroke(Path(ellipseIn: circle), with: .color(textColor.opacity(0.35)), lineWidth: 1.5)
        guard total > 0, done > 0 else { return }
        if done >= total {
            context.fill(Path(ellipseIn: circle), with: .color(color))
            var check = Path()
            check.move(to: CGPoint(x: rect.minX + 3.6, y: rect.midY + 0.3))
            check.addLine(to: CGPoint(x: rect.minX + 6.2, y: rect.maxY - 3.8))
            check.addLine(to: CGPoint(x: rect.maxX - 3.4, y: rect.minY + 3.8))
            context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            return
        }
        // Tortenstück: Anteil der erledigten Aufgaben, oben beginnend.
        let center = CGPoint(x: circle.midX, y: circle.midY)
        var pie = Path()
        pie.move(to: center)
        pie.addArc(center: center, radius: circle.width / 2 - 1.5,
                   startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * Double(done) / Double(total)),
                   clockwise: false)
        pie.closeSubpath()
        context.fill(pie, with: .color(color))
    }

    /// Pfeil aus einem Kasten: „Link öffnen“.
    static func drawLinkIcon(in context: inout GraphicsContext, rect: CGRect, color: Color) {
        let r = rect.insetBy(dx: 1.5, dy: 1.5)
        var box = Path()
        box.move(to: CGPoint(x: r.midX - 0.5, y: r.minY))
        box.addLine(to: CGPoint(x: r.minX, y: r.minY))
        box.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        box.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        box.addLine(to: CGPoint(x: r.maxX, y: r.midY + 0.5))
        context.stroke(box, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        var arrow = Path()
        arrow.move(to: CGPoint(x: r.midX - 0.5, y: r.midY + 0.5))
        arrow.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        arrow.move(to: CGPoint(x: r.maxX - 4.5, y: r.minY))
        arrow.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        arrow.addLine(to: CGPoint(x: r.maxX, y: r.minY + 4.5))
        context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    static func drawNoteIcon(in context: inout GraphicsContext, rect: CGRect, color: Color) {
        let page = rect.insetBy(dx: 2, dy: 1)
        context.stroke(Path(roundedRect: page, cornerRadius: 2), with: .color(color), lineWidth: 1.2)
        var lines = Path()
        for i in 0..<3 {
            let y = page.minY + 3.5 + CGFloat(i) * 2.8
            lines.move(to: CGPoint(x: page.minX + 2.5, y: y))
            lines.addLine(to: CGPoint(x: page.maxX - (i == 2 ? 4 : 2.5), y: y))
        }
        context.stroke(lines, with: .color(color), lineWidth: 1)
    }

    private func drawCollapsedBadge(in context: inout GraphicsContext, node: LayoutNode,
                                    hiddenCount: Int, color: Color) {
        let badge = badgeRect(for: node)
        var link = Path()
        link.move(to: BranchGeometry.outwardPoint(of: node, distance: 0))
        link.addLine(to: CGPoint(x: badge.midX, y: badge.midY))
        context.stroke(link, with: .color(color), lineWidth: 1.5)
        let circle = Path(ellipseIn: badge)
        context.fill(circle, with: .color(Color(hex: palette.canvas)))
        context.stroke(circle, with: .color(color), lineWidth: 1.5)
        let label = Text(hiddenCount > 99 ? "99+" : "\(hiddenCount)")
            .font(.system(size: hiddenCount > 99 ? 7 : 9, weight: .semibold))
            .foregroundStyle(Color(hex: palette.nodeText))
        context.draw(label, at: CGPoint(x: badge.midX, y: badge.midY))
    }

    // MARK: - Griff, Ziehen, Ablegen

    private func drawOverlays(in context: inout GraphicsContext, state: State) {
        if let target = state.dropTarget, let node = layout.nodes[target] {
            let ring = Path(roundedRect: node.frame.insetBy(dx: -7, dy: -7), cornerRadius: 10, style: .continuous)
            context.stroke(ring, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
        }

        if let dragged = state.dragging, let node = layout.nodes[dragged] {
            let ghost = node.frame.offsetBy(dx: state.dragOffset.width, dy: state.dragOffset.height)
            let path = Path(roundedRect: ghost, cornerRadius: 8, style: .continuous)
            context.fill(path, with: .color(Color.accentColor.opacity(0.22)))
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }

        if state.showHandle, let selected = state.selection, let node = layout.nodes[selected] {
            // Einklapp-Knopf „−“ am ausgewählten, aufgeklappten Knoten mit Unterknoten.
            if canToggleCollapse(selected) && !isCollapsed(selected) {
                let fold = badgeRect(for: node)
                let color = Color(hex: branchHex(for: node))
                let circle = Path(ellipseIn: fold)
                context.fill(circle, with: .color(Color(hex: palette.canvas)))
                context.stroke(circle, with: .color(color), lineWidth: 1.5)
                var minus = Path()
                minus.move(to: CGPoint(x: fold.midX - 4.5, y: fold.midY))
                minus.addLine(to: CGPoint(x: fold.midX + 4.5, y: fold.midY))
                context.stroke(minus, with: .color(Color(hex: palette.nodeText)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            let rect = handleRect(for: node, zoom: state.zoom)
            let k = rect.width / (2 * Self.handleRadius)
            context.fill(Path(ellipseIn: rect), with: .color(.accentColor))
            let c = CGPoint(x: rect.midX, y: rect.midY)
            var plus = Path()
            plus.move(to: CGPoint(x: c.x - 4.5 * k, y: c.y))
            plus.addLine(to: CGPoint(x: c.x + 4.5 * k, y: c.y))
            plus.move(to: CGPoint(x: c.x, y: c.y - 4.5 * k))
            plus.addLine(to: CGPoint(x: c.x, y: c.y + 4.5 * k))
            context.stroke(plus, with: .color(.white), style: StrokeStyle(lineWidth: 2 * k, lineCap: .round))
        }
    }
}

extension Path {
    /// Pfad aus den gemeinsamen Umriss-Bausteinen (Formen, Zweige).
    init(elements: [PathElement]) {
        self.init()
        for element in elements {
            switch element {
            case .move(let point): move(to: point)
            case .line(let point): addLine(to: point)
            case .quad(let point, let control): addQuadCurve(to: point, control: control)
            case .curve(let point, let c1, let c2): addCurve(to: point, control1: c1, control2: c2)
            case .close: closeSubpath()
            }
        }
    }
}
