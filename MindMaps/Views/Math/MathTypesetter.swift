import SwiftUI
import AppKit
import CoreText

/// Gesetzte Formel: Maße und Zeichenanweisungen, relativ zur Grundlinie (y wächst nach unten).
struct MathBox: Equatable {
    enum Item: Equatable {
        /// Text mit Grundlinie bei (x, y)
        case glyphs(String, size: CGFloat, italic: Bool, x: CGFloat, y: CGFloat)
        /// Gefüllte Fläche (Bruchstrich, Überstrich)
        case rule(CGRect)
        /// Linienzug (Wurzelzeichen)
        case polyline([CGPoint], width: CGFloat)
    }

    var width: CGFloat = 0
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var items: [Item] = []

    var height: CGFloat { ascent + descent }

    /// Verschiebt alle Bestandteile.
    func offset(dx: CGFloat, dy: CGFloat) -> [Item] {
        items.map { item in
            switch item {
            case .glyphs(let text, let size, let italic, let x, let y):
                return .glyphs(text, size: size, italic: italic, x: x + dx, y: y + dy)
            case .rule(let rect):
                return .rule(rect.offsetBy(dx: dx, dy: dy))
            case .polyline(let points, let width):
                return .polyline(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }, width: width)
            }
        }
    }
}

/// Setzt Formeln (Aufbau wie TeX, stark vereinfacht) mit Times New Roman.
enum MathTypesetter {
    static let baseSize: CGFloat = 15

    // MARK: - Schrift

    static func font(size: CGFloat, italic: Bool) -> NSFont {
        let name = italic ? "TimesNewRomanPS-ItalicMT" : "TimesNewRomanPSMT"
        return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    static func textWidth(_ text: String, size: CGFloat, italic: Bool) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributed = NSAttributedString(string: text, attributes: [.font: font(size: size, italic: italic)])
        let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
        return CGFloat(ceil(width * 100) / 100)
    }

    // MARK: - Zwischenspeicher

    private static var cache: [String: MathBox] = [:]

    /// Gesetzte Formel (zwischengespeichert – die Map zeichnet oft neu).
    static func layout(_ source: String, size: CGFloat = baseSize) -> MathBox {
        let key = "\(size)|\(source)"
        if let cached = cache[key] { return cached }
        let box = layout(MathParser.parse(source), size: size)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = box
        return box
    }

    // MARK: - Setzen

    static func layout(_ atom: MathAtom, size: CGFloat) -> MathBox {
        switch atom {
        case .row(let atoms):
            return row(atoms, size: size)
        case .symbol(let text, let kind):
            return glyphBox(text, size: size, italic: kind == .variable)
        case .text(let text):
            return glyphBox(text, size: size, italic: false)
        case .space(let em):
            return MathBox(width: CGFloat(em) * size, ascent: 0, descent: 0)
        case .fraction(let numerator, let denominator):
            return fraction(numerator, denominator, size: size)
        case .scripts(let base, let sup, let sub):
            return scripts(base, sup: sup, sub: sub, size: size)
        case .root(let radicand, let index):
            return root(radicand, index: index, size: size)
        case .bigOperator(let symbol, _):
            return bigOperator(symbol, size: size)
        case .accent(let base, let mark):
            return accent(base, mark: mark, size: size)
        }
    }

    private static func glyphBox(_ text: String, size: CGFloat, italic: Bool) -> MathBox {
        let width = textWidth(text, size: size, italic: italic)
        // Etwas Platz für kursive Überhänge.
        let extra: CGFloat = italic ? size * 0.04 : 0
        return MathBox(width: width + extra, ascent: size * 0.72, descent: size * 0.22,
                       items: [.glyphs(text, size: size, italic: italic, x: 0, y: 0)])
    }

    private static func append(_ box: MathBox, to row: inout MathBox) {
        row.items += box.offset(dx: row.width, dy: 0)
        row.width += box.width
        row.ascent = max(row.ascent, box.ascent)
        row.descent = max(row.descent, box.descent)
    }

    /// Welche Art hat ein Baustein für die Abstände?
    private static func kind(of atom: MathAtom) -> MathAtom.Kind {
        switch atom {
        case .symbol(_, let kind): return kind
        case .scripts(let base, _, _): return kind(of: base)
        case .bigOperator: return .function
        default: return .ordinary
        }
    }

    private static func row(_ atoms: [MathAtom], size: CGFloat) -> MathBox {
        var box = MathBox()
        var previous: MathAtom.Kind?
        for (i, atom) in atoms.enumerated() {
            var k = kind(of: atom)
            // Minus am Anfang oder nach Rechenzeichen/Klammer: Vorzeichen, kein Abstand.
            if k == .binary, previous == nil || previous == .binary || previous == .relation
                || previous == .punctuation || isOpening(atoms[max(i - 1, 0)]) && i > 0 {
                k = .ordinary
            }
            var space: CGFloat = 0
            if let previous {
                if k == .binary || previous == .binary {
                    space = 0.22
                } else if k == .relation || previous == .relation {
                    space = 0.28
                } else if previous == .punctuation {
                    space = 0.17
                } else if previous == .function, !isOpening(atom), k == .variable || k == .ordinary {
                    space = 0.17
                }
            }
            box.width += space * size
            let child: MathBox
            if case .symbol(let text, let symbolKind) = atom {
                child = glyphBox(text, size: size, italic: symbolKind == .variable)
            } else {
                child = layout(atom, size: size)
            }
            append(child, to: &box)
            previous = k
        }
        return box
    }

    private static func isOpening(_ atom: MathAtom) -> Bool {
        if case .symbol(let text, _) = atom { return ["(", "[", "{", "⟨", "|"].contains(text) }
        return false
    }

    private static func axis(_ size: CGFloat) -> CGFloat { size * 0.26 }
    private static func rule(_ size: CGFloat) -> CGFloat { max(0.8, size * 0.055) }
    private static func smaller(_ size: CGFloat, _ factor: CGFloat) -> CGFloat { max(size * factor, 7) }

    private static func fraction(_ numerator: MathAtom, _ denominator: MathAtom, size: CGFloat) -> MathBox {
        let inner = smaller(size, 0.88)
        let n = layout(numerator, size: inner)
        let d = layout(denominator, size: inner)
        let thickness = rule(size)
        let gap = size * 0.14
        let pad = size * 0.12
        let width = max(n.width, d.width) + 2 * pad
        let lineY = -axis(size)                               // Mitte des Bruchstrichs
        let numBaseline = lineY - thickness / 2 - gap - n.descent
        let denBaseline = lineY + thickness / 2 + gap + d.ascent
        var box = MathBox(width: width,
                          ascent: -numBaseline + n.ascent,
                          descent: denBaseline + d.descent)
        box.items += n.offset(dx: (width - n.width) / 2, dy: numBaseline)
        box.items += d.offset(dx: (width - d.width) / 2, dy: denBaseline)
        box.items.append(.rule(CGRect(x: pad * 0.5, y: lineY - thickness / 2, width: width - pad, height: thickness)))
        return box
    }

    private static func scripts(_ base: MathAtom, sup: MathAtom?, sub: MathAtom?, size: CGFloat) -> MathBox {
        let scriptSize = smaller(size, 0.7)
        let b = layout(base, size: size)
        let supBox = sup.map { layout($0, size: scriptSize) }
        let subBox = sub.map { layout($0, size: scriptSize) }

        if case .bigOperator(_, true) = base {
            // Grenzen darüber und darunter (∑, lim).
            let width = max(b.width, supBox?.width ?? 0, subBox?.width ?? 0)
            var box = MathBox(width: width, ascent: b.ascent, descent: b.descent)
            box.items += b.offset(dx: (width - b.width) / 2, dy: 0)
            let gap = size * 0.12
            if let s = supBox {
                let baseline = -b.ascent - gap - s.descent
                box.items += s.offset(dx: (width - s.width) / 2, dy: baseline)
                box.ascent = -baseline + s.ascent
            }
            if let s = subBox {
                let baseline = b.descent + gap + s.ascent
                box.items += s.offset(dx: (width - s.width) / 2, dy: baseline)
                box.descent = baseline + s.descent
            }
            return box
        }

        var box = b
        let italicCorrection: CGFloat = kind(of: base) == .variable ? size * 0.05 : size * 0.02
        let x = b.width + italicCorrection
        var supShift = max(b.ascent - scriptSize * 0.35, size * 0.38)
        var subShift = max(b.descent + scriptSize * 0.05, size * 0.18)
        if let s = supBox, let t = subBox {
            // Beide: genug Abstand zwischen Hoch- und Tiefzahl.
            let clearance = (supShift - s.descent) - (t.ascent - subShift)
            if clearance < size * 0.12 {
                let fix = (size * 0.12 - clearance) / 2
                supShift += fix
                subShift += fix
            }
        }
        var scriptWidth: CGFloat = 0
        if let s = supBox {
            box.items += s.offset(dx: x, dy: -supShift)
            box.ascent = max(box.ascent, supShift + s.ascent)
            scriptWidth = max(scriptWidth, s.width)
        }
        if let s = subBox {
            box.items += s.offset(dx: b.width + size * 0.02, dy: subShift)
            box.descent = max(box.descent, subShift + s.descent)
            scriptWidth = max(scriptWidth, s.width + (x - b.width - size * 0.02))
        }
        box.width = x + scriptWidth + size * 0.03
        return box
    }

    private static func root(_ radicand: MathAtom, index: MathAtom?, size: CGFloat) -> MathBox {
        let inner = layout(radicand, size: size)
        let thickness = rule(size)
        let gap = size * 0.12
        let sign = size * 0.55
        let top = -(inner.ascent + gap + thickness)
        let bottom = inner.descent
        var box = MathBox(width: sign + inner.width + size * 0.1,
                          ascent: -top + thickness,
                          descent: bottom + size * 0.05)
        var offsetX: CGFloat = 0
        if let index {
            let i = layout(index, size: smaller(size, 0.5))
            offsetX = max(0, i.width - sign * 0.45)
            box.items += i.offset(dx: 0, dy: top * 0.45)
            box.width += offsetX
        }
        let points = [
            CGPoint(x: offsetX + sign * 0.05, y: bottom - (bottom - top) * 0.38),
            CGPoint(x: offsetX + sign * 0.28, y: bottom - (bottom - top) * 0.48),
            CGPoint(x: offsetX + sign * 0.52, y: bottom),
            CGPoint(x: offsetX + sign * 0.92, y: top + thickness / 2),
            CGPoint(x: offsetX + sign + inner.width + size * 0.05, y: top + thickness / 2),
        ]
        box.items.append(.polyline(points, width: thickness))
        box.items += inner.offset(dx: offsetX + sign, dy: 0)
        return box
    }

    private static func bigOperator(_ symbol: String, size: CGFloat) -> MathBox {
        guard symbol.count == 1 else {
            // lim, max, … aufrecht in normaler Größe
            return glyphBox(symbol, size: size, italic: false)
        }
        let big = size * 1.45
        let width = textWidth(symbol, size: big, italic: false)
        // Zeichen mittig zur Mathe-Achse ausrichten.
        let baseline = big * 0.3 - axis(size) + size * 0.02
        return MathBox(width: width + size * 0.1, ascent: big * 0.72 - baseline, descent: baseline + big * 0.22,
                       items: [.glyphs(symbol, size: big, italic: false, x: size * 0.05, y: baseline)])
    }

    private static func accent(_ base: MathAtom, mark: String, size: CGFloat) -> MathBox {
        let b = layout(base, size: size)
        var box = b
        if mark == "¯" {
            let thickness = rule(size)
            let y = -b.ascent - size * 0.1
            box.items.append(.rule(CGRect(x: 0, y: y - thickness, width: b.width, height: thickness)))
            box.ascent = -y + thickness
            return box
        }
        let markSize = smaller(size, 0.75)
        let markWidth = textWidth(mark, size: markSize, italic: false)
        let baseline = -b.ascent + markSize * 0.35
        box.items.append(.glyphs(mark, size: markSize, italic: false,
                                 x: (b.width - markWidth) / 2 + size * 0.05, y: baseline))
        box.ascent = max(b.ascent, -baseline + markSize * 0.45)
        box.width = max(b.width, markWidth)
        return box
    }

    // MARK: - Zeichnen

    /// Zeichnet die Formel; `origin` ist der Anfang der Grundlinie.
    static func draw(_ box: MathBox, in context: inout GraphicsContext, origin: CGPoint, color: Color) {
        let resolved = NSColor(color).usingColorSpace(.sRGB)?.cgColor ?? NSColor.textColor.cgColor
        context.withCGContext { cg in
            cg.saveGState()
            cg.translateBy(x: origin.x, y: origin.y)
            cg.setFillColor(resolved)
            cg.setStrokeColor(resolved)
            for item in box.items {
                switch item {
                case .glyphs(let text, let size, let italic, let x, let y):
                    let attributed = NSAttributedString(string: text, attributes: [
                        .font: font(size: size, italic: italic),
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): resolved,
                    ])
                    let line = CTLineCreateWithAttributedString(attributed)
                    cg.saveGState()
                    // CoreText zeichnet mit y nach oben – die Map hat y nach unten.
                    cg.textMatrix = .identity
                    cg.translateBy(x: x, y: y)
                    cg.scaleBy(x: 1, y: -1)
                    cg.textPosition = .zero
                    CTLineDraw(line, cg)
                    cg.restoreGState()
                case .rule(let rect):
                    cg.fill(rect)
                case .polyline(let points, let width):
                    guard let first = points.first else { continue }
                    cg.setLineWidth(width)
                    cg.setLineJoin(.round)
                    cg.setLineCap(.round)
                    cg.beginPath()
                    cg.move(to: first)
                    for point in points.dropFirst() { cg.addLine(to: point) }
                    cg.strokePath()
                }
            }
            cg.restoreGState()
        }
    }

    /// SVG-Elemente der Formel; `origin` ist der Anfang der Grundlinie.
    static func svg(_ box: MathBox, origin: CGPoint, color: String) -> [String] {
        func n(_ v: CGFloat) -> String {
            let rounded = (v * 100).rounded() / 100
            if rounded == rounded.rounded() { return String(Int(rounded)) }
            return String(format: "%.2f", Double(rounded))
        }
        return box.items.map { item in
            switch item {
            case .glyphs(let text, let size, let italic, let x, let y):
                return "<text x=\"\(n(origin.x + x))\" y=\"\(n(origin.y + y))\" font-family=\"'Times New Roman', Times, serif\" "
                    + "font-size=\"\(n(size))\"\(italic ? " font-style=\"italic\"" : "") fill=\"\(color)\" xml:space=\"preserve\">"
                    + XMLText.escape(text) + "</text>"
            case .rule(let rect):
                return "<rect x=\"\(n(origin.x + rect.minX))\" y=\"\(n(origin.y + rect.minY))\" width=\"\(n(rect.width))\" "
                    + "height=\"\(n(rect.height))\" fill=\"\(color)\"/>"
            case .polyline(let points, let width):
                let d = points.enumerated().map { i, p in
                    (i == 0 ? "M" : "L") + "\(n(origin.x + p.x)) \(n(origin.y + p.y))"
                }.joined(separator: " ")
                return "<path d=\"\(d)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(n(width))\" "
                    + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
            }
        }
    }
}
