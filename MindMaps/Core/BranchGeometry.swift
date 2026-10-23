import Foundation

/// Verlauf der Zweige zwischen Eltern- und Kindknoten – je nach Layout (M8).
/// Die App und der SVG-Export zeichnen beide mit diesen Punkten.
enum BranchGeometry {
    /// Wie ein Zweig andockt.
    enum Rule: Equatable {
        /// seitlich (horizontales Layout)
        case horizontal
        /// oben/unten (vertikales Layout, Hauptäste im kompakten Layout)
        case vertical
        /// eingerückte Liste (kompaktes Layout)
        case list
        /// vom Mittelpunkt nach außen (radiales Layout)
        case radial
    }

    static func rule(for kind: MapStyle.Layout, childDepth: Int) -> Rule {
        switch kind {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        case .compact: return childDepth <= 1 ? .vertical : .list
        case .radial: return .radial
        }
    }

    /// Mittellinie eines Zweigs.
    /// - Parameters:
    ///   - parentInset: So weit beginnt der Zweig im Elternknoten (beim Hauptknoten mit Fläche 6 Punkte).
    ///   - parentShape, childShape: Bei „Linie“ dockt der Zweig an der Linie unter dem Text an, bei Kreis und Wolke am Umriss.
    static func centerline(parent: LayoutNode, child: LayoutNode, kind: MapStyle.Layout,
                           style: Theme.BranchStyle, parentInset: CGFloat = 0,
                           parentShape: Theme.NodeShape = .rounded, childShape: Theme.NodeShape = .rounded) -> [PathElement] {
        let rule = child.branchRule ?? self.rule(for: kind, childDepth: child.depth)
        var elements = rawCenterline(parent: parent, child: child, rule: rule, style: style, parentInset: parentInset,
                                     parentUnderlined: parentShape == .line, childUnderlined: childShape == .line,
                                     parentRound: roundShapes.contains(parentShape))
        // Runde Formen (und alle Formen im radialen Layout): genau am Umriss andocken.
        func adjusts(_ shape: Theme.NodeShape) -> Bool {
            roundShapes.contains(shape) || (rule == .radial && shape != .line && shape != .embedded)
        }
        if adjusts(childShape), let last = elements.last, let end = endPoint(of: last) {
            elements[elements.count - 1] = replacingEndPoint(of: last,
                with: ShapeGeometry.edgePoint(childShape, in: child.frame, toward: end))
        }
        if parentInset == 0, adjusts(parentShape), case .move(let start)? = elements.first {
            elements[0] = .move(ShapeGeometry.edgePoint(parentShape, in: parent.frame, toward: start))
        }
        return elements
    }

    /// Formen, deren Rand nicht am umgebenden Rechteck liegt.
    static let roundShapes: Set<Theme.NodeShape> = [.circle, .cloud]

    private static func endPoint(of element: PathElement) -> CGPoint? {
        switch element {
        case .move(let p), .line(let p): return p
        case .quad(let p, _): return p
        case .curve(let p, _, _): return p
        case .close: return nil
        }
    }

    private static func replacingEndPoint(of element: PathElement, with point: CGPoint) -> PathElement {
        switch element {
        case .move: return .move(point)
        case .line: return .line(point)
        case .quad(_, let control): return .quad(point, control: control)
        case .curve(_, let c1, let c2): return .curve(point, control1: c1, control2: c2)
        case .close: return .close
        }
    }

    private static func rawCenterline(parent: LayoutNode, child: LayoutNode, rule: Rule, style: Theme.BranchStyle,
                                      parentInset: CGFloat, parentUnderlined: Bool, childUnderlined: Bool,
                                      parentRound: Bool) -> [PathElement] {
        let p = parent.frame, c = child.frame
        switch rule {
        case .horizontal:
            return horizontal(p, c, style: style, inset: parentInset,
                              parentUnderlined: parentUnderlined, childUnderlined: childUnderlined)
        case .vertical:
            let down = c.midY >= p.midY
            let start = CGPoint(x: p.midX, y: down ? p.maxY - parentInset : p.minY + parentInset)
            let end = CGPoint(x: c.midX, y: down ? c.minY : c.maxY)
            let midY = (start.y + end.y) / 2
            switch style {
            case .curved:
                return [.move(start), .curve(end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))]
            case .angled:
                return [.move(start), .line(CGPoint(x: start.x, y: midY)), .line(CGPoint(x: end.x, y: midY)), .line(end)]
            }
        case .list:
            // Liste nach unten (oder, im vertikalen Layout „nach oben“, nach oben).
            let down = c.midY >= p.midY
            let x = parentRound ? p.midX : p.minX + min(12, p.width / 2)
            let start = CGPoint(x: x, y: down ? p.maxY : p.minY)
            let end = CGPoint(x: c.minX, y: childUnderlined ? c.maxY : c.midY)
            // Von Hand verschoben, sodass die Liste nicht mehr passt: seitlich andocken.
            guard end.x > x + 2, abs(end.y - start.y) > 2, (end.y > start.y) == down else {
                return horizontal(p, c, style: style, inset: parentInset,
                                  parentUnderlined: parentUnderlined, childUnderlined: childUnderlined)
            }
            switch style {
            case .angled:
                return [.move(start), .line(CGPoint(x: x, y: end.y)), .line(end)]
            case .curved:
                let r = min(10, abs(end.y - start.y), end.x - x)
                let before = CGPoint(x: x, y: down ? end.y - r : end.y + r)
                return [.move(start), .line(before),
                        .quad(CGPoint(x: x + r, y: end.y), control: CGPoint(x: x, y: end.y)), .line(end)]
            }
        case .radial:
            let pc = CGPoint(x: p.midX, y: p.midY), cc = CGPoint(x: c.midX, y: c.midY)
            let start = ShapeGeometry.boundaryPoint(of: p, toward: cc, margin: -parentInset)
            let end = ShapeGeometry.boundaryPoint(of: c, toward: pc)
            guard style == .curved else { return [.move(start), .line(end)] }
            let distance = hypot(end.x - start.x, end.y - start.y)
            // Beim Elternknoten halb radial, halb Richtung Kind – so entstehen keine S-Kurven.
            let direct = normalized(CGVector(dx: cc.x - pc.x, dy: cc.y - pc.y))
            var out = direct
            if parent.depth > 0 {
                let radial = normalized(parent.growth)
                out = normalized(CGVector(dx: radial.dx + direct.dx, dy: radial.dy + direct.dy))
            }
            let into = normalized(child.growth)
            let c1 = CGPoint(x: start.x + out.dx * distance * 0.35, y: start.y + out.dy * distance * 0.35)
            let c2 = CGPoint(x: end.x - into.dx * distance * 0.35, y: end.y - into.dy * distance * 0.35)
            return [.move(start), .curve(end, control1: c1, control2: c2)]
        }
    }

    private static func horizontal(_ p: CGRect, _ c: CGRect, style: Theme.BranchStyle, inset: CGFloat,
                                   parentUnderlined: Bool, childUnderlined: Bool) -> [PathElement] {
        let toRight = c.midX >= p.midX
        let start = CGPoint(x: toRight ? p.maxX - inset : p.minX + inset, y: parentUnderlined ? p.maxY : p.midY)
        let end = CGPoint(x: toRight ? c.minX : c.maxX, y: childUnderlined ? c.maxY : c.midY)
        let midX = (start.x + end.x) / 2
        switch style {
        case .curved:
            return [.move(start), .curve(end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))]
        case .angled:
            return [.move(start), .line(CGPoint(x: midX, y: start.y)), .line(CGPoint(x: midX, y: end.y)), .line(end)]
        }
    }

    // MARK: - Echt verjüngte Zweige

    /// Fläche eines Zweigs, der von `startWidth` gleichmäßig auf `endWidth` dünner wird.
    static func taperedOutline(_ centerline: [PathElement], startWidth: CGFloat, endWidth: CGFloat) -> [PathElement] {
        var points: [CGPoint] = []
        for point in centerline.flattened(steps: 18) {
            if let last = points.last, hypot(last.x - point.x, last.y - point.y) < 0.01 { continue }
            points.append(point)
        }
        guard points.count >= 2 else { return [] }

        var lengths: [CGFloat] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }
        let total = max(lengths.last ?? 1, 0.001)

        func normal(_ a: CGPoint, _ b: CGPoint) -> CGVector {
            normalized(CGVector(dx: -(b.y - a.y), dy: b.x - a.x))
        }

        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in points.indices {
            let width = startWidth + (endWidth - startWidth) * lengths[i] / total
            var n: CGVector
            var scale: CGFloat = 1
            if i == 0 {
                n = normal(points[0], points[1])
            } else if i == points.count - 1 {
                n = normal(points[i - 1], points[i])
            } else {
                let n1 = normal(points[i - 1], points[i]), n2 = normal(points[i], points[i + 1])
                n = normalized(CGVector(dx: n1.dx + n2.dx, dy: n1.dy + n2.dy))
                // Gehrung an Ecken (eckige Zweige), begrenzt.
                scale = 1 / max(n.dx * n1.dx + n.dy * n1.dy, 0.5)
            }
            let half = width / 2 * scale
            left.append(CGPoint(x: points[i].x + n.dx * half, y: points[i].y + n.dy * half))
            right.append(CGPoint(x: points[i].x - n.dx * half, y: points[i].y - n.dy * half))
        }
        return ShapeGeometry.polygon(left + right.reversed())
    }

    static func normalized(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        guard length > 0.000001 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: v.dx / length, dy: v.dy / length)
    }

    // MARK: - Griffe

    /// Punkt außerhalb des Knotens in Wachstumsrichtung (für „+“-Griff und Zähler).
    static func outwardPoint(of node: LayoutNode, distance: CGFloat) -> CGPoint {
        let v = normalized(node.growth)
        let c = CGPoint(x: node.frame.midX, y: node.frame.midY)
        let far = CGPoint(x: c.x + v.dx * 10_000, y: c.y + v.dy * 10_000)
        let edge = ShapeGeometry.boundaryPoint(of: node.frame, toward: far)
        return CGPoint(x: edge.x + v.dx * distance, y: edge.y + v.dy * distance)
    }
}
