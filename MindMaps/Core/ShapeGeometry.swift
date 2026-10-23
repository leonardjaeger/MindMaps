import Foundation

/// Ein Stück eines Umrisses. Die App macht daraus einen `Path`, der SVG-Export `d="…"` –
/// so sehen Formen und Zweige in der Map, im Export und im Ausdruck gleich aus (M8).
enum PathElement: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case quad(CGPoint, control: CGPoint)
    case curve(CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

extension Array where Element == PathElement {
    /// SVG-Pfad („M… L… C… Z“), Zahlen mit höchstens einer Nachkommastelle.
    func svgPathData() -> String {
        func n(_ v: CGFloat) -> String { ShapeGeometry.number(v) }
        func p(_ point: CGPoint) -> String { "\(n(point.x)) \(n(point.y))" }
        return map { element in
            switch element {
            case .move(let point): return "M\(p(point))"
            case .line(let point): return "L\(p(point))"
            case .quad(let point, let control): return "Q\(p(control)) \(p(point))"
            case .curve(let point, let c1, let c2): return "C\(p(c1)) \(p(c2)) \(p(point))"
            case .close: return "Z"
            }
        }
        .joined(separator: " ")
    }

    /// Punkte entlang des Pfads; Kurven werden in `steps` Stücke geteilt.
    func flattened(steps: Int = 12) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        for element in self {
            switch element {
            case .move(let point):
                points.append(point)
                current = point
                start = point
            case .line(let point):
                points.append(point)
                current = point
            case .quad(let point, let control):
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    points.append(CGPoint(x: u * u * current.x + 2 * u * t * control.x + t * t * point.x,
                                          y: u * u * current.y + 2 * u * t * control.y + t * t * point.y))
                }
                current = point
            case .curve(let point, let c1, let c2):
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    points.append(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * point.x,
                                          y: a * current.y + b * c1.y + c * c2.y + d * point.y))
                }
                current = point
            case .close:
                if current != start { points.append(start) }
                current = start
            }
        }
        return points
    }
}

/// Die 10 Knotenformen: Größe (damit der Inhalt hineinpasst) und Umriss.
enum ShapeGeometry {
    static let minimumWidth: CGFloat = 36
    /// Höhe der „Beulen“ der Wolke.
    static let cloudBump: CGFloat = 6

    /// Knotengröße für einen Inhalt (Text, Bild, Formel, Tags) der Größe `content`.
    static func frameSize(_ shape: Theme.NodeShape, content: CGSize, padding: CGSize) -> CGSize {
        let w = content.width, h = content.height
        let pw = padding.width, ph = padding.height
        switch shape {
        case .rounded, .rectangle, .line, .embedded:
            return CGSize(width: max(w + 2 * pw, minimumWidth), height: h + 2 * ph)
        case .pill:
            let height = h + 2 * ph
            return CGSize(width: max(ceil(w + 2 * pw + height * 0.35), minimumWidth), height: height)
        case .square:
            let side = max(w + 2 * pw, h + 2 * ph, minimumWidth)
            return CGSize(width: side, height: side)
        case .circle:
            let diameter = max(ceil((w * w + h * h).squareRoot() + 2 * max(ph, 5)), minimumWidth)
            return CGSize(width: diameter, height: diameter)
        case .cloud:
            // Inhalt passt in die Ellipse innerhalb der Beulen (Faktor √2 für die Ecken, etwas Luft).
            let a = w / 2 * 1.42 + pw, b = h / 2 * 1.42 + ph
            return CGSize(width: max(ceil(2 * (a + cloudBump)), minimumWidth), height: ceil(2 * (b + cloudBump)))
        case .hexagon:
            let height = h + 2 * ph
            let k = hexagonInset(width: .greatestFiniteMagnitude, height: height)
            return CGSize(width: max(ceil(w + 2 * pw + 2 * k * h / height), minimumWidth), height: height)
        case .octagon:
            var width = w + 2 * pw, height = h + 2 * ph
            for _ in 0..<400 {
                let cut = octagonCut(width: width, height: height)
                if w / 2 + h / 2 + 3 <= width / 2 + height / 2 - cut { break }
                width += 2
                height += 1
            }
            return CGSize(width: max(ceil(width), minimumWidth), height: ceil(height))
        }
    }

    static func hexagonInset(width: CGFloat, height: CGFloat) -> CGFloat {
        min(height * 0.35, width / 3)
    }

    static func octagonCut(width: CGFloat, height: CGFloat) -> CGFloat {
        min(width, height) * 0.29
    }

    /// Umriss der Form; Linie und Eingebettet haben keinen.
    static func outline(_ shape: Theme.NodeShape, in rect: CGRect) -> [PathElement] {
        switch shape {
        case .rounded: return roundedRect(rect, radius: min(10, rect.height / 3, rect.width / 2))
        case .rectangle, .square: return roundedRect(rect, radius: 2)
        case .pill: return roundedRect(rect, radius: min(rect.width, rect.height) / 2)
        case .circle: return ellipse(rect)
        case .cloud: return cloud(rect)
        case .hexagon:
            let k = hexagonInset(width: rect.width, height: rect.height)
            return polygon([CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.minX + k, y: rect.minY),
                            CGPoint(x: rect.maxX - k, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                            CGPoint(x: rect.maxX - k, y: rect.maxY), CGPoint(x: rect.minX + k, y: rect.maxY)])
        case .octagon:
            let c = octagonCut(width: rect.width, height: rect.height)
            return polygon([CGPoint(x: rect.minX + c, y: rect.minY), CGPoint(x: rect.maxX - c, y: rect.minY),
                            CGPoint(x: rect.maxX, y: rect.minY + c), CGPoint(x: rect.maxX, y: rect.maxY - c),
                            CGPoint(x: rect.maxX - c, y: rect.maxY), CGPoint(x: rect.minX + c, y: rect.maxY),
                            CGPoint(x: rect.minX, y: rect.maxY - c), CGPoint(x: rect.minX, y: rect.minY + c)])
        case .line, .embedded:
            return []
        }
    }

    /// Linie unter dem Text (Form „Linie“).
    static func underline(_ rect: CGRect) -> [PathElement] {
        [.move(CGPoint(x: rect.minX, y: rect.maxY)), .line(CGPoint(x: rect.maxX, y: rect.maxY))]
    }

    // MARK: - Bausteine

    static func polygon(_ points: [CGPoint]) -> [PathElement] {
        guard let first = points.first else { return [] }
        return [.move(first)] + points.dropFirst().map { .line($0) } + [.close]
    }

    /// Kreisbogen-Näherung mit kubischen Kurven.
    private static let kappa: CGFloat = 0.5523

    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> [PathElement] {
        let r = max(0, min(radius, rect.width / 2, rect.height / 2))
        guard r > 0 else {
            return polygon([CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)])
        }
        let k = kappa * r
        let (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        return [
            .move(CGPoint(x: x0 + r, y: y0)),
            .line(CGPoint(x: x1 - r, y: y0)),
            .curve(CGPoint(x: x1, y: y0 + r), control1: CGPoint(x: x1 - r + k, y: y0), control2: CGPoint(x: x1, y: y0 + r - k)),
            .line(CGPoint(x: x1, y: y1 - r)),
            .curve(CGPoint(x: x1 - r, y: y1), control1: CGPoint(x: x1, y: y1 - r + k), control2: CGPoint(x: x1 - r + k, y: y1)),
            .line(CGPoint(x: x0 + r, y: y1)),
            .curve(CGPoint(x: x0, y: y1 - r), control1: CGPoint(x: x0 + r - k, y: y1), control2: CGPoint(x: x0, y: y1 - r + k)),
            .line(CGPoint(x: x0, y: y0 + r)),
            .curve(CGPoint(x: x0 + r, y: y0), control1: CGPoint(x: x0, y: y0 + r - k), control2: CGPoint(x: x0 + r - k, y: y0)),
            .close,
        ]
    }

    static func ellipse(_ rect: CGRect) -> [PathElement] {
        let rx = rect.width / 2, ry = rect.height / 2
        let kx = kappa * rx, ky = kappa * ry
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return [
            .move(CGPoint(x: c.x + rx, y: c.y)),
            .curve(CGPoint(x: c.x, y: c.y + ry), control1: CGPoint(x: c.x + rx, y: c.y + ky), control2: CGPoint(x: c.x + kx, y: c.y + ry)),
            .curve(CGPoint(x: c.x - rx, y: c.y), control1: CGPoint(x: c.x - kx, y: c.y + ry), control2: CGPoint(x: c.x - rx, y: c.y + ky)),
            .curve(CGPoint(x: c.x, y: c.y - ry), control1: CGPoint(x: c.x - rx, y: c.y - ky), control2: CGPoint(x: c.x - kx, y: c.y - ry)),
            .curve(CGPoint(x: c.x + rx, y: c.y), control1: CGPoint(x: c.x + kx, y: c.y - ry), control2: CGPoint(x: c.x + rx, y: c.y - ky)),
            .close,
        ]
    }

    /// Wolke: gleichmäßig verteilte Beulen auf einer Ellipse.
    static func cloud(_ rect: CGRect) -> [PathElement] {
        let bump = min(cloudBump, rect.width / 6, rect.height / 6)
        let a = rect.width / 2 - bump, b = rect.height / 2 - bump
        guard a > 1, b > 1 else { return ellipse(rect) }
        let c = CGPoint(x: rect.midX, y: rect.midY)

        // Punkte auf der Ellipse, gleich weit voneinander entfernt (nach Bogenlänge).
        let fine = 360
        var samples: [CGPoint] = []
        var lengths: [CGFloat] = [0]
        for i in 0...fine {
            let t = CGFloat(i) / CGFloat(fine) * 2 * .pi - .pi / 2
            let point = CGPoint(x: c.x + a * cos(t), y: c.y + b * sin(t))
            if let last = samples.last { lengths.append(lengths.last! + hypot(point.x - last.x, point.y - last.y)) }
            samples.append(point)
        }
        let perimeter = lengths.last!
        let count = max(8, Int((perimeter / 24).rounded()))
        var anchors: [CGPoint] = []
        var index = 0
        for k in 0..<count {
            let target = perimeter * CGFloat(k) / CGFloat(count)
            while index < lengths.count - 1 && lengths[index] < target { index += 1 }
            anchors.append(samples[index])
        }

        var elements: [PathElement] = [.move(anchors[0])]
        for k in 0..<count {
            let p = anchors[k], q = anchors[(k + 1) % count]
            let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
            var nx = q.y - p.y, ny = -(q.x - p.x)
            let length = max(hypot(nx, ny), 0.001)
            nx /= length
            ny /= length
            if nx * (mid.x - c.x) + ny * (mid.y - c.y) < 0 { nx = -nx; ny = -ny }
            // Eine quadratische Kurve weicht in der Mitte um die Hälfte des Kontrollpunkt-Abstands ab.
            let control = CGPoint(x: mid.x + nx * 2 * bump, y: mid.y + ny * 2 * bump)
            elements.append(.quad(q, control: control))
        }
        elements.append(.close)
        return elements
    }

    // MARK: - Hilfen

    /// Liegt ein Punkt im (geschlossenen) Umriss? (Strahlverfahren auf dem geglätteten Umriss.)
    static func contains(_ outline: [PathElement], _ point: CGPoint) -> Bool {
        let polygon = outline.flattened(steps: 16)
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Punkt auf dem Rand von `rect` in Richtung `target` (vom Mittelpunkt aus), `margin` nach außen.
    static func boundaryPoint(of rect: CGRect, toward target: CGPoint, margin: CGFloat = 0) -> CGPoint {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - c.x, dy = target.y - c.y
        guard dx != 0 || dy != 0 else { return c }
        let sx = dx == 0 ? CGFloat.infinity : max(rect.width / 2 + margin, 0) / abs(dx)
        let sy = dy == 0 ? CGFloat.infinity : max(rect.height / 2 + margin, 0) / abs(dy)
        let s = min(sx, sy)
        return CGPoint(x: c.x + dx * s, y: c.y + dy * s)
    }

    /// Wo ein Strahl vom Mittelpunkt in Richtung `target` den Umriss verlässt
    /// (damit Zweige auch bei Kreis und Wolke genau am Rand andocken).
    static func edgePoint(_ shape: Theme.NodeShape, in rect: CGRect, toward target: CGPoint) -> CGPoint {
        let outline = self.outline(shape, in: rect)
        guard !outline.isEmpty else { return target }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let d = CGPoint(x: target.x - c.x, y: target.y - c.y)
        guard hypot(d.x, d.y) > 0.001 else { return target }
        let polygon = outline.flattened(steps: 10)
        var best: CGFloat?
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let e = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let denominator = d.x * e.y - d.y * e.x
            guard abs(denominator) > 1e-9 else { continue }
            let t = ((a.x - c.x) * e.y - (a.y - c.y) * e.x) / denominator
            let u = ((a.x - c.x) * d.y - (a.y - c.y) * d.x) / denominator
            if t > 0, u >= -1e-6, u <= 1 + 1e-6 { best = max(best ?? t, t) }
        }
        guard let t = best else { return target }
        return CGPoint(x: c.x + d.x * t, y: c.y + d.y * t)
    }

    /// Zahl mit höchstens einer Nachkommastelle, immer mit Punkt (für SVG).
    static func number(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", Double(rounded))
    }
}
