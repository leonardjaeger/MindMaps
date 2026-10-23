import Foundation

enum MoveDirection: Equatable {
    case up, down, left, right

    var vector: CGPoint {
        switch self {
        case .up: return CGPoint(x: 0, y: -1)
        case .down: return CGPoint(x: 0, y: 1)
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        }
    }
}

/// Pfeiltasten-Navigation in der Mindmap – für alle vier Layouts (M8).
///
/// - In Wachstumsrichtung eines Knotens geht es zum (mittleren) Unterknoten, entgegengesetzt zum Elternknoten.
///   Horizontal ist das rechts/links, vertikal unten/oben, radial nach außen/innen.
/// - Quer dazu wechselt man zum Geschwisterknoten; gibt es keinen, zum nächstgelegenen Knoten in dieser Richtung.
/// - Eingerückte Listen (kompaktes Layout, Blätter im vertikalen Layout): hoch/runter folgt der Liste,
///   rechts führt zum ersten Unterknoten, links zum Elternknoten.
enum MapNavigation {
    static func target(from id: UUID?, direction: MoveDirection,
                       layout: MindMapLayout, rootID: UUID) -> UUID? {
        guard let id, let current = layout.nodes[id] else { return rootID }
        let v = direction.vector
        let children = layout.nodes.values.filter { $0.parentID == current.id }

        // Hauptknoten: Unterknoten in dieser Richtung, sonst der nächste Knoten dorthin.
        guard let parentID = current.parentID else {
            let toward = children.filter { along(from: current, to: $0, v) > 0.3 }
            return nearestChild(toward, of: current, direction: v) ?? nearest(to: current, direction: v, in: layout)
        }

        if isListItem(current, in: layout) {
            switch direction {
            case .left: return parentID
            case .right: return layout.order.first { layout.nodes[$0]?.parentID == current.id }
            case .up, .down:
                if layout.kind == .compact {
                    // Kompakt: eine Spalte pro Hauptast, Zeile für Zeile wie in der Gliederung.
                    let column = layout.nodes.values.filter {
                        $0.branchIndex == current.branchIndex && $0.depth >= 1 && projection(current, $0, v) > 0.001
                    }
                    if let next = column.min(by: { projection(current, $0, v) < projection(current, $1, v) }) {
                        return next.id
                    }
                }
                return sibling(of: current, direction: v, in: layout, sameSide: false)
                    ?? nearest(to: current, direction: v, in: layout)
            }
        }

        let growth = normalized(current.growth)
        let outward = growth.x * v.x + growth.y * v.y
        if outward > 0.5 {
            let toward = children.filter { projection(current, $0, v) > 0 }
            return nearestChild(toward, of: current, direction: v)
        }
        if outward < -0.5 {
            return parentID
        }
        let sameSide = layout.nodes[parentID]?.parentID == nil && (layout.kind == .horizontal || layout.kind == .vertical)
        return sibling(of: current, direction: v, in: layout, sameSide: sameSide)
            ?? nearest(to: current, direction: v, in: layout)
    }

    /// Steht der Knoten in einer eingerückten Liste?
    private static func isListItem(_ node: LayoutNode, in layout: MindMapLayout) -> Bool {
        let rule = node.branchRule ?? BranchGeometry.rule(for: layout.kind, childDepth: node.depth)
        return rule == .list
    }

    private static func normalized(_ v: CGVector) -> CGPoint {
        let length = hypot(v.dx, v.dy)
        guard length > 0.000001 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: v.dx / length, y: v.dy / length)
    }

    /// Kosinus zwischen Richtung `v` und der Linie von `a` nach `b` (1 = genau in Richtung).
    private static func along(from a: LayoutNode, to b: LayoutNode, _ v: CGPoint) -> CGFloat {
        let dx = b.frame.midX - a.frame.midX, dy = b.frame.midY - a.frame.midY
        let length = hypot(dx, dy)
        guard length > 0.001 else { return 0 }
        return (dx * v.x + dy * v.y) / length
    }

    /// Abstand quer zur Richtung (bei links/rechts: senkrechter Abstand).
    private static func across(_ a: LayoutNode, _ b: LayoutNode, _ v: CGPoint) -> CGFloat {
        let dx = b.frame.midX - a.frame.midX, dy = b.frame.midY - a.frame.midY
        return abs(dx * v.y - dy * v.x)
    }

    private static func projection(_ a: LayoutNode, _ b: LayoutNode, _ v: CGPoint) -> CGFloat {
        (b.frame.midX - a.frame.midX) * v.x + (b.frame.midY - a.frame.midY) * v.y
    }

    /// Der Unterknoten, der am wenigsten seitlich versetzt ist (bei Gleichstand der obere).
    private static func nearestChild(_ children: [LayoutNode], of node: LayoutNode, direction v: CGPoint) -> UUID? {
        children.min { a, b in
            let da = across(node, a, v), db = across(node, b, v)
            if abs(da - db) > 0.001 { return da < db }
            if abs(a.frame.midY - b.frame.midY) > 0.001 { return a.frame.midY < b.frame.midY }
            return a.frame.midX < b.frame.midX
        }?
        .id
    }

    /// Nächster Geschwisterknoten in Richtung `v` (Hauptäste nur auf derselben Seite).
    private static func sibling(of node: LayoutNode, direction v: CGPoint, in layout: MindMapLayout,
                                sameSide: Bool) -> UUID? {
        guard let parent = node.parentID else { return nil }
        let candidates = layout.nodes.values.filter {
            $0.parentID == parent && $0.id != node.id && (!sameSide || $0.side == node.side)
                && projection(node, $0, v) > 0.001 && along(from: node, to: $0, v) > 0.3
        }
        return candidates.min { projection(node, $0, v) < projection(node, $1, v) }?.id
    }

    /// Nächster Knoten jenseits der Kante in Richtung `v`; seitlicher Abstand zählt doppelt –
    /// so bleibt man möglichst in derselben Spalte bzw. Zeile.
    private static func nearest(to node: LayoutNode, direction v: CGPoint, in layout: MindMapLayout) -> UUID? {
        let halfExtent = abs(v.x) * node.frame.width / 2 + abs(v.y) * node.frame.height / 2
        let candidates = layout.nodes.values.filter { other in
            other.id != node.id && projection(node, other, v) > halfExtent
        }
        return candidates.min { score($0, from: node, v) < score($1, from: node, v) }?.id
    }

    private static func score(_ candidate: LayoutNode, from node: LayoutNode, _ v: CGPoint) -> CGFloat {
        projection(node, candidate, v) + 2 * across(node, candidate, v)
    }
}
