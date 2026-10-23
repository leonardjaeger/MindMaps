import Foundation

/// Die vier Layouts (M8): horizontal, vertikal, kompakt und radial.
///
/// Alle Layouts sind überlappungsfrei gebaut: Jeder Teilbaum bekommt einen eigenen Streifen
/// (horizontal/vertikal/kompakt) bzw. einen eigenen Winkelbereich auf seinem Ring (radial).
/// Danach kommen die von Hand verschobenen Knoten dazu (`Node.offset`, Unterknoten wandern mit).
enum MapLayoutEngine {
    static func layout(root: Node, style: MapStyle = MapStyle(),
                       measure: (Node, Int) -> CGSize) -> MindMapLayout {
        var sizes: [UUID: CGSize] = [:]
        let cachedMeasure: (Node, Int) -> CGSize = { node, depth in
            if let size = sizes[node.id] { return size }
            let size = measure(node, depth)
            sizes[node.id] = size
            return size
        }
        var layout: MindMapLayout
        switch style.layout {
        case .horizontal:
            layout = TreeLayout.layout(root: root,
                                       spacing: TreeLayout.Spacing(horizontal: 44 * style.levelSpacing,
                                                                   vertical: 12 * style.siblingSpacing),
                                       sides: style.sides, measure: cachedMeasure)
        case .vertical:
            layout = VerticalLayout.layout(root: root, style: style, measure: cachedMeasure)
        case .compact:
            layout = CompactLayout.layout(root: root, style: style, measure: cachedMeasure)
        case .radial:
            layout = RadialLayout.layout(root: root, style: style, measure: cachedMeasure)
        }
        layout.kind = style.layout
        applyBranchColors(root, to: &layout)
        applyOffsets(root, to: &layout)
        return layout
    }

    /// Eigene Zweigfarben gelten für den Knoten und alle Unterknoten.
    static func applyBranchColors(_ root: Node, to layout: inout MindMapLayout) {
        func visit(_ node: Node, inherited: String?) {
            let color = node.style?.branchColor ?? inherited
            layout.nodes[node.id]?.branchColor = color
            guard !node.isCollapsed else { return }
            for child in node.children { visit(child, inherited: color) }
        }
        visit(root, inherited: nil)
    }

    /// Von Hand verschobene Knoten: Verschiebung auf den Knoten und seine Unterknoten anwenden.
    static func applyOffsets(_ root: Node, to layout: inout MindMapLayout) {
        var moved = false
        func visit(_ node: Node, dx: CGFloat, dy: CGFloat) {
            var x = dx, y = dy
            if let offset = node.offset, node.id != root.id {
                x += CGFloat(offset.x)
                y += CGFloat(offset.y)
            }
            if x != 0 || y != 0, let placed = layout.nodes[node.id] {
                layout.nodes[node.id]?.frame = placed.frame.offsetBy(dx: x, dy: y)
                moved = true
            }
            guard !node.isCollapsed else { return }
            for child in node.children { visit(child, dx: x, dy: y) }
        }
        visit(root, dx: 0, dy: 0)
        if moved {
            layout.bounds = layout.nodes.values.reduce(layout.nodes[root.id]?.frame ?? .zero) { $0.union($1.frame) }
        }
    }

    /// Frames aller Knoten, die sich überlappen (für Tests und die Abnahme).
    static func overlaps(in layout: MindMapLayout, tolerance: CGFloat = 0.5) -> [(UUID, UUID)] {
        let placed = Array(layout.nodes.values)
        var result: [(UUID, UUID)] = []
        for i in placed.indices {
            for j in placed.indices where j > i {
                if placed[i].frame.insetBy(dx: tolerance, dy: tolerance)
                    .intersects(placed[j].frame.insetBy(dx: tolerance, dy: tolerance)) {
                    result.append((placed[i].id, placed[j].id))
                }
            }
        }
        return result
    }
}

// MARK: - Vertikal

/// Hauptknoten oben, Unterknoten in einer Reihe darunter (wie ein Organigramm).
/// Hat ein Knoten nur noch Blätter als Unterknoten, stehen diese eingerückt untereinander –
/// so wird die Map nicht beliebig breit. „Oben und unten“ verteilt die Hauptäste auf beide Richtungen.
enum VerticalLayout {
    static let indent: CGFloat = 24

    static func layout(root: Node, style: MapStyle, measure: (Node, Int) -> CGSize) -> MindMapLayout {
        let levelGap = 44 * CGFloat(style.levelSpacing)
        let siblingGap = 18 * CGFloat(style.siblingSpacing)
        let listGap = 8 * CGFloat(style.siblingSpacing)
        let listStart = 14 * CGFloat(style.levelSpacing)
        var widths: [UUID: CGFloat] = [:]

        /// Unterknoten untereinander statt nebeneinander? (Nur Blätter, nicht am Hauptknoten.)
        func stacks(_ node: Node, _ depth: Int) -> Bool {
            depth >= 1 && !node.isCollapsed && !node.children.isEmpty
                && node.children.allSatisfy { $0.isCollapsed || $0.children.isEmpty }
        }

        func subtreeWidth(_ node: Node, _ depth: Int) -> CGFloat {
            if let w = widths[node.id] { return w }
            let own = measure(node, depth).width
            var w = own
            if stacks(node, depth) {
                let widest = node.children.map { measure($0, depth + 1).width }.max() ?? 0
                w = max(own, indent + widest)
            } else if !node.isCollapsed && !node.children.isEmpty {
                w = max(own, rowWidth(node.children, depth + 1))
            }
            widths[node.id] = w
            return w
        }

        func rowWidth(_ nodes: [Node], _ depth: Int) -> CGFloat {
            nodes.reduce(0) { $0 + subtreeWidth($1, depth) } + siblingGap * CGFloat(max(nodes.count - 1, 0))
        }

        var result: [UUID: LayoutNode] = [:]
        var order: [UUID] = []
        let rootSize = measure(root, 0)
        let rootFrame = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2,
                               width: rootSize.width, height: rootSize.height)
        let rootGrowth = CGVector(dx: 0, dy: style.sides == .secondary ? -1 : 1)
        result[root.id] = LayoutNode(id: root.id, parentID: nil, frame: rootFrame, depth: 0, side: .center,
                                     branchIndex: -1, growth: rootGrowth)
        order.append(root.id)

        func add(_ child: Node, frame: CGRect, parentID: UUID, depth: Int, down: Bool, branch: Int,
                 rule: BranchGeometry.Rule) {
            result[child.id] = LayoutNode(id: child.id, parentID: parentID, frame: frame, depth: depth,
                                          side: down ? .right : .left, branchIndex: branch,
                                          growth: CGVector(dx: 0, dy: down ? 1 : -1), branchRule: rule)
            order.append(child.id)
        }

        /// Unterknoten von `parent` (dessen Teilbaum den Streifen ab `left` belegt).
        func placeChildren(of node: Node, frame parent: CGRect, left: CGFloat, down: Bool, depth: Int, branch: Int) {
            guard !node.isCollapsed, !node.children.isEmpty else { return }
            if stacks(node, depth - 1) {
                var y = down ? parent.maxY + listStart : parent.minY - listStart
                for child in node.children {
                    let size = measure(child, depth)
                    if !down { y -= size.height }
                    let frame = CGRect(x: parent.minX + indent, y: y, width: size.width, height: size.height)
                    add(child, frame: frame, parentID: node.id, depth: depth, down: down, branch: branch, rule: .list)
                    y = down ? frame.maxY + listGap : frame.minY - listGap
                }
                return
            }
            var x = left + (subtreeWidth(node, depth - 1) - rowWidth(node.children, depth)) / 2
            for child in node.children {
                place(child, left: x, parent: parent, parentID: node.id, down: down, depth: depth, branch: branch)
                x += subtreeWidth(child, depth) + siblingGap
            }
        }

        /// Knoten mittig in seinem Streifen [left, left + Teilbaumbreite].
        func place(_ node: Node, left: CGFloat, parent: CGRect, parentID: UUID, down: Bool, depth: Int, branch: Int) {
            let w = subtreeWidth(node, depth)
            let size = measure(node, depth)
            let y = down ? parent.maxY + levelGap : parent.minY - levelGap - size.height
            var x = left + w / 2 - size.width / 2
            // Gestapelte Blätter hängen links am Knoten – dann den Knoten links in den Streifen setzen.
            if stacks(node, depth) { x = left + (w - max(size.width, w)) / 2 }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            add(node, frame: frame, parentID: parentID, depth: depth, down: down, branch: branch, rule: .vertical)
            placeChildren(of: node, frame: frame, left: left, down: down, depth: depth + 1, branch: branch)
        }

        if !root.isCollapsed {
            let downCount: Int
            switch style.sides {
            case .both: downCount = (root.children.count + 1) / 2
            case .primary: downCount = root.children.count
            case .secondary: downCount = 0
            }
            for (down, range) in [(true, 0..<downCount), (false, downCount..<root.children.count)] {
                let group = Array(root.children[range])
                var x = rootFrame.midX - rowWidth(group, 1) / 2
                for (offset, child) in group.enumerated() {
                    place(child, left: x, parent: rootFrame, parentID: root.id, down: down, depth: 1,
                          branch: range.lowerBound + offset)
                    x += subtreeWidth(child, 1) + siblingGap
                }
            }
        }
        let bounds = result.values.reduce(rootFrame) { $0.union($1.frame) }
        return MindMapLayout(nodes: result, order: order, bounds: bounds, kind: .vertical)
    }
}

// MARK: - Kompakt

/// Hauptknoten oben, die Hauptäste als Spalten darunter; in jeder Spalte stehen die Unterknoten
/// eingerückt untereinander – wie eine Gliederung. Braucht am wenigsten Platz.
enum CompactLayout {
    /// Einrückung pro Ebene.
    static let indent: CGFloat = 24

    static func layout(root: Node, style: MapStyle, measure: (Node, Int) -> CGSize) -> MindMapLayout {
        let levelGap = 40 * CGFloat(style.levelSpacing)
        let rowGap = 8 * CGFloat(style.siblingSpacing)
        let columnGap = 28 * CGFloat(style.siblingSpacing)
        var sizes: [UUID: CGSize] = [:]

        /// Breite und Höhe einer eingerückten Liste (Knoten + alle sichtbaren Unterknoten).
        func listSize(_ node: Node, _ depth: Int) -> CGSize {
            if let s = sizes[node.id] { return s }
            let own = measure(node, depth)
            var width = own.width, height = own.height
            if !node.isCollapsed {
                for child in node.children {
                    let s = listSize(child, depth + 1)
                    width = max(width, indent + s.width)
                    height += rowGap + s.height
                }
            }
            let s = CGSize(width: width, height: height)
            sizes[node.id] = s
            return s
        }

        var result: [UUID: LayoutNode] = [:]
        var order: [UUID] = []
        let rootSize = measure(root, 0)
        let rootFrame = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2,
                               width: rootSize.width, height: rootSize.height)
        result[root.id] = LayoutNode(id: root.id, parentID: nil, frame: rootFrame, depth: 0, side: .center,
                                     branchIndex: -1, growth: CGVector(dx: 0, dy: 1))
        order.append(root.id)

        func placeList(_ node: Node, x: CGFloat, y: CGFloat, parentID: UUID, depth: Int, branch: Int) {
            let size = measure(node, depth)
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            result[node.id] = LayoutNode(id: node.id, parentID: parentID, frame: frame, depth: depth,
                                         side: .right, branchIndex: branch, growth: CGVector(dx: 1, dy: 0))
            order.append(node.id)
            guard !node.isCollapsed else { return }
            var cursor = frame.maxY + rowGap
            for child in node.children {
                placeList(child, x: x + indent, y: cursor, parentID: node.id, depth: depth + 1, branch: branch)
                cursor += listSize(child, depth + 1).height + rowGap
            }
        }

        if !root.isCollapsed && !root.children.isEmpty {
            let columns = root.children.map { listSize($0, 1) }
            let total = columns.reduce(0) { $0 + $1.width } + columnGap * CGFloat(columns.count - 1)
            var x = -total / 2
            for (index, child) in root.children.enumerated() {
                placeList(child, x: x, y: rootFrame.maxY + levelGap, parentID: root.id, depth: 1, branch: index)
                x += columns[index].width + columnGap
            }
        }
        let bounds = result.values.reduce(rootFrame) { $0.union($1.frame) }
        return MindMapLayout(nodes: result, order: order, bounds: bounds, kind: .compact)
    }
}

// MARK: - Radial

/// Hauptknoten in der Mitte, jede Ebene auf einem Ring darum.
///
/// Jeder Knoten bekommt einen Winkelbereich (nach Zahl der Blätter darunter); seine Unterknoten
/// teilen sich diesen Bereich. Der Ringradius wird so groß gewählt, dass jeder Knoten ganz in
/// seinem Winkelbereich liegt und der Ring nicht in den inneren Ring ragt – dann kann sich nichts überlappen.
enum RadialLayout {
    /// Abstand zwischen Nachbarn auf einem Ring (Punkte).
    static let neighborGap: CGFloat = 10

    private struct Item {
        let node: Node
        let depth: Int
        let parentID: UUID
        let branch: Int
        let angle: CGFloat
        let lower: CGFloat
        let upper: CGFloat
        let size: CGSize
    }

    static func layout(root: Node, style: MapStyle, measure: (Node, Int) -> CGSize) -> MindMapLayout {
        let ringGap = 48 * CGFloat(style.levelSpacing)
        let gap = neighborGap * CGFloat(style.siblingSpacing)

        // Winkelbedarf: Ein Knoten braucht quer zum Radius so viel Platz, wie er dort breit ist –
        // oben und unten also seine Breite, links und rechts nur seine Höhe. Zuerst wird mit einer
        // Schätzung verteilt, dann zweimal mit den tatsächlichen Winkeln nachgebessert.
        var angles: [UUID: CGFloat] = [:]
        var weights: [UUID: CGFloat] = [:]
        func extent(_ node: Node, _ depth: Int) -> CGFloat {
            let size = measure(node, depth)
            guard let angle = angles[node.id] else { return (size.width + size.height) / 2 + gap }
            return abs(size.width * sin(angle)) + abs(size.height * cos(angle)) + gap
        }
        func weight(_ node: Node, _ depth: Int) -> CGFloat {
            if let w = weights[node.id] { return w }
            var w = extent(node, depth)
            if !node.isCollapsed && !node.children.isEmpty {
                w = max(w, node.children.reduce(0) { $0 + weight($1, depth + 1) })
            }
            weights[node.id] = w
            return w
        }

        // Winkelbereiche verteilen (oben beginnen, im Uhrzeigersinn).
        var rings: [[Item]] = []
        func assign(_ children: [Node], lower: CGFloat, upper: CGFloat, parentID: UUID, depth: Int, branch: Int?) {
            let total = children.reduce(CGFloat(0)) { $0 + weight($1, depth) }
            var start = lower
            for (index, child) in children.enumerated() {
                let span = (upper - lower) * weight(child, depth) / max(total, 0.001)
                let item = Item(node: child, depth: depth, parentID: parentID, branch: branch ?? index,
                                angle: start + span / 2, lower: start, upper: start + span,
                                size: measure(child, depth))
                while rings.count < depth { rings.append([]) }
                rings[depth - 1].append(item)
                if !child.isCollapsed && !child.children.isEmpty {
                    assign(child.children, lower: start, upper: start + span, parentID: child.id,
                           depth: depth + 1, branch: branch ?? index)
                }
                start += span
            }
        }

        let rootSize = measure(root, 0)
        let rootFrame = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2,
                               width: rootSize.width, height: rootSize.height)
        if !root.isCollapsed && !root.children.isEmpty {
            for pass in 0..<3 {
                if pass > 0 {
                    angles = Dictionary(uniqueKeysWithValues: rings.joined().map { ($0.node.id, $0.angle) })
                    weights = [:]
                    rings = []
                }
                assign(root.children, lower: -.pi / 2, upper: 1.5 * .pi, parentID: root.id, depth: 1, branch: nil)
            }
        }

        var result: [UUID: LayoutNode] = [:]
        result[root.id] = LayoutNode(id: root.id, parentID: nil, frame: rootFrame, depth: 0, side: .center,
                                     branchIndex: -1, growth: CGVector(dx: 1, dy: 0))
        // Erst die kleinsten möglichen Radien, dann gleichmäßige Abstände zwischen den Ringen
        // (sieht ruhiger aus; ein größerer Radius verletzt keine Bedingung).
        var outer = maxDistance(of: rootFrame)
        var step: CGFloat = 0
        for (index, ring) in rings.enumerated() {
            let radius = ringRadius(for: ring, inner: outer + ringGap, gap: gap)
            step = max(step, radius / CGFloat(index + 1))
            outer = ring.map { maxDistance(of: rect($0.size, at: radius, angle: $0.angle)) }.max() ?? outer
        }
        outer = maxDistance(of: rootFrame)
        for (index, ring) in rings.enumerated() {
            // Gleichmäßig, aber höchstens 1,5-mal so weit draußen wie nötig (sonst wird die Map riesig).
            let needed = ringRadius(for: ring, inner: outer + ringGap, gap: gap)
            let radius = max(needed, min(step * CGFloat(index + 1), needed * 1.5))
            for item in ring {
                let frame = rect(item.size, at: radius, angle: item.angle)
                result[item.node.id] = LayoutNode(id: item.node.id, parentID: item.parentID, frame: frame,
                                                  depth: item.depth, side: cos(item.angle) >= -0.0001 ? .right : .left,
                                                  branchIndex: item.branch,
                                                  growth: CGVector(dx: cos(item.angle), dy: sin(item.angle)))
                outer = max(outer, maxDistance(of: frame))
            }
        }

        // Zeichenreihenfolge: Eltern vor Kindern.
        var order: [UUID] = []
        func visit(_ node: Node) {
            guard result[node.id] != nil else { return }
            order.append(node.id)
            guard !node.isCollapsed else { return }
            node.children.forEach(visit)
        }
        visit(root)
        let bounds = result.values.reduce(rootFrame) { $0.union($1.frame) }
        return MindMapLayout(nodes: result, order: order, bounds: bounds, kind: .radial)
    }

    private static func rect(_ size: CGSize, at radius: CGFloat, angle: CGFloat) -> CGRect {
        CGRect(x: radius * cos(angle) - size.width / 2, y: radius * sin(angle) - size.height / 2,
               width: size.width, height: size.height)
    }

    /// Größter Abstand einer Ecke vom Mittelpunkt.
    private static func maxDistance(of rect: CGRect) -> CGFloat {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map { hypot($0.x, $0.y) }.max() ?? 0
    }

    /// Kleinster Abstand des Rechtecks vom Mittelpunkt.
    private static func minDistance(of rect: CGRect) -> CGFloat {
        let dx = max(rect.minX, 0, -rect.maxX)
        let dy = max(rect.minY, 0, -rect.maxY)
        return hypot(dx, dy)
    }

    /// Passt das Rechteck (vom Mittelpunkt aus gesehen) in seinen Winkelbereich – mit Abstand `gap`?
    private static func fits(_ item: Item, radius: CGFloat, inner: CGFloat, gap: CGFloat) -> Bool {
        let frame = rect(item.size, at: radius, angle: item.angle)
        let near = minDistance(of: frame)
        guard near >= inner else { return false }
        let span = item.upper - item.lower
        if span >= 2 * .pi - 0.0001 { return true }
        let margin = (gap / 2) / max(near, 1)
        for corner in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
            var delta = atan2(corner.y, corner.x) - item.angle
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            if abs(delta) > span / 2 - margin { return false }
        }
        return true
    }

    /// Kleinster Radius, bei dem alle Knoten des Rings in ihren Bereich passen.
    private static func ringRadius(for ring: [Item], inner: CGFloat, gap: CGFloat) -> CGFloat {
        func ok(_ r: CGFloat) -> Bool { ring.allSatisfy { fits($0, radius: r, inner: inner, gap: gap) } }
        var low = inner
        var high = max(inner * 2, 200)
        var guardCount = 0
        while !ok(high) && guardCount < 40 {
            low = high
            high *= 2
            guardCount += 1
        }
        if ok(low) { return low }
        for _ in 0..<40 {
            let mid = (low + high) / 2
            if ok(mid) { high = mid } else { low = mid }
            if high - low < 0.5 { break }
        }
        return ceil(high)
    }
}
