import Foundation

/// Position eines Knotens in der berechneten Mindmap.
struct LayoutNode: Equatable {
    enum Side: Equatable { case center, left, right }

    let id: UUID
    let parentID: UUID?
    var frame: CGRect
    let depth: Int
    let side: Side
    /// Index des Hauptastes (bestimmt die Zweigfarbe); -1 beim Hauptknoten.
    let branchIndex: Int
    /// Richtung, in die Unterknoten wachsen (Einheitsvektor) – dort sitzen „+“-Griff und Zähler (M8).
    var growth: CGVector
    /// Eigene Zweigfarbe (am Knoten oder von einem Vorfahren geerbt), sonst `nil` (M8).
    var branchColor: String?
    /// Wie der Zweig zu diesem Knoten andockt; `nil` = Standard des Layouts (M8).
    var branchRule: BranchGeometry.Rule?

    init(id: UUID, parentID: UUID?, frame: CGRect, depth: Int, side: Side, branchIndex: Int,
         growth: CGVector? = nil, branchColor: String? = nil, branchRule: BranchGeometry.Rule? = nil) {
        self.id = id
        self.parentID = parentID
        self.frame = frame
        self.depth = depth
        self.side = side
        self.branchIndex = branchIndex
        self.growth = growth ?? CGVector(dx: side == .left ? -1 : 1, dy: 0)
        self.branchColor = branchColor
        self.branchRule = branchRule
    }
}

struct MindMapLayout: Equatable {
    var nodes: [UUID: LayoutNode]
    /// Zeichenreihenfolge: Eltern vor Kindern.
    var order: [UUID]
    var bounds: CGRect
    /// Art des Layouts – bestimmt, wie die Zweige andocken (M8).
    var kind: MapStyle.Layout = .horizontal

    init(nodes: [UUID: LayoutNode], order: [UUID], bounds: CGRect, kind: MapStyle.Layout = .horizontal) {
        self.nodes = nodes
        self.order = order
        self.bounds = bounds
        self.kind = kind
    }
}

/// Horizontales Mindmap-Layout: Hauptknoten in der Mitte, erste Hälfte der Äste rechts, Rest links.
///
/// Die Größe jedes Knotens liefert `measure` (in der App: Textgröße + Innenabstand).
/// Die Berechnung ist reine Geometrie und kommt ohne SwiftUI aus.
enum TreeLayout {
    struct Spacing: Equatable {
        var horizontal: CGFloat = 44
        var vertical: CGFloat = 12
    }

    static func layout(root: Node,
                       spacing: Spacing = Spacing(),
                       sides: MapStyle.Sides = .both,
                       measure: (Node, Int) -> CGSize) -> MindMapLayout {
        var sizes: [UUID: CGSize] = [:]
        var heights: [UUID: CGFloat] = [:]

        func size(_ node: Node, _ depth: Int) -> CGSize {
            if let s = sizes[node.id] { return s }
            let s = measure(node, depth)
            sizes[node.id] = s
            return s
        }

        func stackHeight(_ nodes: [Node], _ depth: Int) -> CGFloat {
            guard !nodes.isEmpty else { return 0 }
            let sum = nodes.reduce(CGFloat(0)) { $0 + subtreeHeight($1, depth) }
            return sum + spacing.vertical * CGFloat(nodes.count - 1)
        }

        func subtreeHeight(_ node: Node, _ depth: Int) -> CGFloat {
            if let h = heights[node.id] { return h }
            let own = size(node, depth).height
            let h = (node.isCollapsed || node.children.isEmpty)
                ? own
                : max(own, stackHeight(node.children, depth + 1))
            heights[node.id] = h
            return h
        }

        var result: [UUID: LayoutNode] = [:]
        var order: [UUID] = []

        let rootSize = size(root, 0)
        let rootFrame = CGRect(x: -rootSize.width / 2, y: -rootSize.height / 2,
                               width: rootSize.width, height: rootSize.height)
        result[root.id] = LayoutNode(id: root.id, parentID: nil, frame: rootFrame,
                                     depth: 0, side: .center, branchIndex: -1)
        order.append(root.id)

        func place(_ children: [(node: Node, branch: Int)], parent: LayoutNode,
                   side: LayoutNode.Side, depth: Int) {
            let nodes = children.map(\.node)
            var y = parent.frame.midY - stackHeight(nodes, depth) / 2
            for (child, branch) in children {
                let h = subtreeHeight(child, depth)
                let s = size(child, depth)
                let x = side == .right
                    ? parent.frame.maxX + spacing.horizontal
                    : parent.frame.minX - spacing.horizontal - s.width
                let frame = CGRect(x: x, y: y + h / 2 - s.height / 2, width: s.width, height: s.height)
                let placed = LayoutNode(id: child.id, parentID: parent.id, frame: frame,
                                        depth: depth, side: side, branchIndex: branch)
                result[child.id] = placed
                order.append(child.id)
                if !child.isCollapsed && !child.children.isEmpty {
                    place(child.children.map { ($0, branch) }, parent: placed, side: side, depth: depth + 1)
                }
                y += h + spacing.vertical
            }
        }

        if !root.isCollapsed {
            let indexed = root.children.enumerated().map { (node: $0.element, branch: $0.offset) }
            let rightCount: Int
            switch sides {
            case .both: rightCount = (indexed.count + 1) / 2
            case .primary: rightCount = indexed.count
            case .secondary: rightCount = 0
            }
            place(Array(indexed.prefix(rightCount)), parent: result[root.id]!, side: .right, depth: 1)
            place(Array(indexed.dropFirst(rightCount)), parent: result[root.id]!, side: .left, depth: 1)
        }

        let bounds = result.values.reduce(rootFrame) { $0.union($1.frame) }
        return MindMapLayout(nodes: result, order: order, bounds: bounds)
    }
}
