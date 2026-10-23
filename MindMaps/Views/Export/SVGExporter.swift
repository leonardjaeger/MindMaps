import AppKit

/// SVG-Export: zeichnet die Mindmap wie `MapRenderer`, aber als SVG-Text (öffnet sich in jedem Browser).
@MainActor
enum SVGExporter {
    static let padding: CGFloat = 40

    static func svg(for data: MindMapDocumentData, assets: [String: Data] = [:], transparent: Bool = false) -> String {
        let scene = MapExportScene(data: data, assets: assets)
        let bounds = scene.contentBounds(padding: padding)
        var out: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(n(bounds.width))\" height=\"\(n(bounds.height))\" "
                + "viewBox=\"\(n(bounds.minX)) \(n(bounds.minY)) \(n(bounds.width)) \(n(bounds.height))\">",
            "<title>\(XMLText.escape(data.root.text))</title>",
        ]
        if !transparent {
            out.append("<rect x=\"\(n(bounds.minX))\" y=\"\(n(bounds.minY))\" width=\"\(n(bounds.width))\" "
                       + "height=\"\(n(bounds.height))\" \(paint("fill", scene.palette.canvas))/>")
        }
        out.append(#"<g fill="none" stroke-linecap="round" stroke-linejoin="round">"#)
        out += branches(scene)
        out.append("</g>")
        out += connections(scene)
        out.append("<g font-family=\"\(fontFamily(scene.theme.font))\">")
        out += nodes(scene)
        out.append("</g>")
        out.append("</svg>")
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: - Zweige

    /// Gleiche Geometrie wie in der App (`MapRenderer.branch(to:)`): verjüngte Zweige als Fläche.
    private static func branches(_ scene: MapExportScene) -> [String] {
        var out: [String] = []
        let renderer = scene.renderer
        for id in scene.layout.order {
            guard let node = scene.layout.nodes[id], let drawing = renderer.branch(to: node) else { continue }
            if let outline = drawing.taperedOutline {
                out.append("<path d=\"\(outline.svgPathData())\" \(paint("fill", drawing.color)) stroke=\"none\"/>")
            } else {
                out.append("<path d=\"\(drawing.centerline.svgPathData())\" \(paint("stroke", drawing.color)) "
                           + "stroke-width=\"\(n(drawing.width))\"/>")
            }
        }
        return out
    }

    // MARK: - Knoten

    private static func nodes(_ scene: MapExportScene) -> [String] {
        var out: [String] = []
        let renderer = scene.renderer
        for id in scene.layout.order {
            guard let node = scene.layout.nodes[id], let model = renderer.model(id),
                  let look = renderer.appearance(for: node) else { continue }
            let rect = node.frame

            // Form wie in der App (M8: 10 Formen, eigener Stil).
            let outline = ShapeGeometry.outline(look.shape, in: rect)
            if !outline.isEmpty {
                var element = "<path d=\"\(outline.svgPathData())\" " + (look.fill.map { paint("fill", $0) } ?? "fill=\"none\"")
                if let border = look.border {
                    element += " \(paint("stroke", border)) stroke-width=\"\(n(CGFloat(look.borderWidth)))\""
                }
                out.append(element + "/>")
            } else if let fill = look.fill {
                out.append("<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\" width=\"\(n(rect.width))\" "
                           + "height=\"\(n(rect.height))\" rx=\"6\" \(paint("fill", fill))/>")
            }
            if look.shape == .line {
                out.append("<path d=\"\(ShapeGeometry.underline(rect).svgPathData())\" fill=\"none\" \(paint("stroke", look.branch)) "
                           + "stroke-width=\"\(n(scene.metrics.underlineWidth(depth: node.depth)))\" stroke-linecap=\"round\"/>")
            }

            if model.isCollapsed && !model.children.isEmpty {
                out += badge(for: node, hiddenCount: model.nodeCount - 1,
                             color: node.depth == 0 ? (look.fill ?? look.branch) : look.branch, scene: scene)
            }

            let content = scene.metrics.contentLayout(of: model, depth: node.depth, frame: rect)
            out += decorations(content, look: look, scene: scene)
            if let r = content.imageRect, let image = model.image {
                if let uri = scene.images.dataURI(image.asset) {
                    out.append("<image x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" "
                               + "preserveAspectRatio=\"none\" href=\"\(uri)\"/>")
                } else {
                    out.append("<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" "
                               + "rx=\"6\" fill=\"#8B8D98\" fill-opacity=\"0.2\"/>")
                }
            }
            if let origin = content.formulaOrigin, let box = content.decor.formula {
                out += MathTypesetter.svg(box, origin: origin, color: svgColor(look.text))
            }
            guard content.decor.showsText else { continue }
            out.append(text(model, node: node, content: content, color: look.text, scene: scene))
        }
        return out
    }

    /// Kästchen bzw. Fortschritt, Notiz-Symbol und Tags – wie in der App.
    private static func decorations(_ content: NodeContentLayout, look: NodeAppearance,
                                    scene: MapExportScene) -> [String] {
        var out: [String] = []
        let textHex = look.text
        let accent = look.accent
        if let r = content.leadingRect, let leading = content.decor.leading {
            let box = r.insetBy(dx: 0.75, dy: 0.75)
            func check(_ inset: CGFloat) -> String {
                "<path d=\"M\(n(r.minX + inset)) \(n(r.midY + 0.3)) L\(n(r.minX + inset + 2.8)) \(n(r.maxY - 3.6)) "
                    + "L\(n(r.maxX - inset + 0.2)) \(n(r.minY + 3.6))\" fill=\"none\" stroke=\"#FFFFFF\" "
                    + "stroke-width=\"1.8\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
            }
            switch leading {
            case .checkbox(.open):
                out.append("<rect x=\"\(n(box.minX))\" y=\"\(n(box.minY))\" width=\"\(n(box.width))\" height=\"\(n(box.height))\" "
                           + "rx=\"3.5\" fill=\"none\" \(paint("stroke", textHex)) stroke-opacity=\"0.7\" stroke-width=\"1.5\"/>")
            case .checkbox(.partial):
                out.append("<rect x=\"\(n(box.minX))\" y=\"\(n(box.minY))\" width=\"\(n(box.width))\" height=\"\(n(box.height))\" "
                           + "rx=\"3.5\" fill=\"none\" \(paint("stroke", accent)) stroke-width=\"1.5\"/>")
                out.append("<path d=\"M\(n(r.minX + 3.5)) \(n(r.midY)) L\(n(r.maxX - 3.5)) \(n(r.midY))\" "
                           + "\(paint("stroke", accent)) stroke-width=\"2\" stroke-linecap=\"round\"/>")
            case .checkbox(.done):
                out.append("<rect x=\"\(n(box.minX))\" y=\"\(n(box.minY))\" width=\"\(n(box.width))\" height=\"\(n(box.height))\" "
                           + "rx=\"3.5\" \(paint("fill", accent))/>")
                out.append(check(3.2))
            case .progress(let done, let total):
                let c = r.insetBy(dx: 1, dy: 1)
                out.append("<circle cx=\"\(n(c.midX))\" cy=\"\(n(c.midY))\" r=\"\(n(c.width / 2))\" fill=\"none\" "
                           + "\(paint("stroke", textHex)) stroke-opacity=\"0.35\" stroke-width=\"1.5\"/>")
                if total > 0, done >= total {
                    out.append("<circle cx=\"\(n(c.midX))\" cy=\"\(n(c.midY))\" r=\"\(n(c.width / 2))\" \(paint("fill", accent))/>")
                    out.append(check(3.6))
                } else if total > 0, done > 0 {
                    let radius = c.width / 2 - 1.5
                    let angle = -Double.pi / 2 + 2 * Double.pi * Double(done) / Double(total)
                    let end = CGPoint(x: c.midX + radius * CGFloat(cos(angle)), y: c.midY + radius * CGFloat(sin(angle)))
                    let large = Double(done) / Double(total) > 0.5 ? 1 : 0
                    out.append("<path d=\"M\(n(c.midX)) \(n(c.midY)) L\(n(c.midX)) \(n(c.midY - radius)) "
                               + "A\(n(radius)) \(n(radius)) 0 \(large) 1 \(n(end.x)) \(n(end.y)) Z\" \(paint("fill", accent))/>")
                }
            }
        }
        if let r = content.noteRect {
            let page = r.insetBy(dx: 2, dy: 1)
            var d = ""
            for i in 0..<3 {
                let y = page.minY + 3.5 + CGFloat(i) * 2.8
                d += "M\(n(page.minX + 2.5)) \(n(y)) L\(n(page.maxX - (i == 2 ? 4 : 2.5))) \(n(y)) "
            }
            out.append("<g fill=\"none\" \(paint("stroke", textHex)) stroke-opacity=\"0.65\">"
                       + "<rect x=\"\(n(page.minX))\" y=\"\(n(page.minY))\" width=\"\(n(page.width))\" height=\"\(n(page.height))\" rx=\"2\" stroke-width=\"1.2\"/>"
                       + "<path d=\"\(d)\" stroke-width=\"1\"/></g>")
        }
        if let r = content.linkRect {
            let b = r.insetBy(dx: 1.5, dy: 1.5)
            let d = "M\(n(b.midX - 0.5)) \(n(b.minY)) L\(n(b.minX)) \(n(b.minY)) L\(n(b.minX)) \(n(b.maxY)) "
                + "L\(n(b.maxX)) \(n(b.maxY)) L\(n(b.maxX)) \(n(b.midY + 0.5)) "
                + "M\(n(b.midX - 0.5)) \(n(b.midY + 0.5)) L\(n(b.maxX)) \(n(b.minY)) "
                + "M\(n(b.maxX - 4.5)) \(n(b.minY)) L\(n(b.maxX)) \(n(b.minY)) L\(n(b.maxX)) \(n(b.minY + 4.5))"
            out.append("<path d=\"\(d)\" fill=\"none\" \(paint("stroke", accent)) stroke-width=\"1.4\" "
                       + "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
        }
        for (tag, r) in content.tagRects {
            out.append("<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" "
                       + "rx=\"\(n(r.height / 2))\" \(paint("fill", scene.tagCatalog.hex(for: tag)))/>")
            out.append("<text x=\"\(n(r.midX))\" y=\"\(n(r.midY))\" text-anchor=\"middle\" dominant-baseline=\"central\" "
                       + "font-size=\"9\" font-weight=\"600\" fill=\"#FFFFFF\">\(XMLText.escape(tag))</text>")
        }
        return out
    }

    private static func text(_ model: Node, node: LayoutNode, content: NodeContentLayout, color: String,
                             scene: MapExportScene) -> String {
        let depth = node.depth
        let metrics = scene.metrics
        let font = metrics.nsFont(for: model, depth: depth)
        let x = content.textRect.minX
        let lines = lineLayout(NodeMetrics.displayText(model), font: font)
        var element = "<text x=\"\(n(x))\" font-size=\"\(n(metrics.fontSize(for: model, depth: depth)))\" "
            + "font-weight=\"\(weight(metrics.weight(for: model, depth: depth)))\" \(paint("fill", color))"
        if metrics.fontFamily(for: model) != scene.theme.font {
            element += " font-family=\"\(fontFamily(metrics.fontFamily(for: model)))\""
        }
        if metrics.isItalic(model) { element += " font-style=\"italic\"" }
        if model.text.isEmpty { element += " opacity=\"0.5\"" }
        element += " xml:space=\"preserve\">"
        for line in lines {
            element += "<tspan x=\"\(n(x))\" y=\"\(n(content.textRect.minY + line.baseline))\">"
                + XMLText.escape(line.text) + "</tspan>"
        }
        return element + "</text>"
    }

    private static func badge(for node: LayoutNode, hiddenCount: Int, color: String, scene: MapExportScene) -> [String] {
        let rect = scene.renderer.badgeRect(for: node)
        let from = BranchGeometry.outwardPoint(of: node, distance: 0)
        let label = hiddenCount > 99 ? "99+" : "\(hiddenCount)"
        return [
            "<path d=\"M\(n(from.x)) \(n(from.y)) L\(n(rect.midX)) \(n(rect.midY))\" fill=\"none\" \(paint("stroke", color)) stroke-width=\"1.5\"/>",
            "<circle cx=\"\(n(rect.midX))\" cy=\"\(n(rect.midY))\" r=\"\(n(rect.width / 2))\" "
                + "\(paint("fill", scene.palette.canvas)) \(paint("stroke", color)) stroke-width=\"1.5\"/>",
            "<text x=\"\(n(rect.midX))\" y=\"\(n(rect.midY))\" text-anchor=\"middle\" dominant-baseline=\"central\" "
                + "font-size=\"\(hiddenCount > 99 ? 7 : 9)\" font-weight=\"600\" \(paint("fill", scene.palette.nodeText))>\(label)</text>",
        ]
    }

    // MARK: - Querverbindungen (M7)

    private static func connections(_ scene: MapExportScene) -> [String] {
        let renderer = scene.renderer
        var out: [String] = []
        let color = scene.palette.nodeText
        for connection in scene.connections {
            guard let g = renderer.geometry(for: connection) else { continue }
            out.append("<path d=\"M\(n(g.start.x)) \(n(g.start.y)) Q\(n(g.control.x)) \(n(g.control.y)) \(n(g.end.x)) \(n(g.end.y))\" "
                       + "fill=\"none\" \(paint("stroke", color)) stroke-opacity=\"0.6\" stroke-width=\"1.8\" "
                       + "stroke-dasharray=\"6 4\" stroke-linecap=\"round\"/>")
            let dx = g.end.x - g.control.x, dy = g.end.y - g.control.y
            let length = max(hypot(dx, dy), 0.001)
            let ux = dx / length, uy = dy / length, size: CGFloat = 9
            let p1 = CGPoint(x: g.end.x - ux * size - uy * size * 0.55, y: g.end.y - uy * size + ux * size * 0.55)
            let p2 = CGPoint(x: g.end.x - ux * size + uy * size * 0.55, y: g.end.y - uy * size - ux * size * 0.55)
            out.append("<path d=\"M\(n(g.end.x)) \(n(g.end.y)) L\(n(p1.x)) \(n(p1.y)) L\(n(p2.x)) \(n(p2.y)) Z\" "
                       + "\(paint("fill", color)) fill-opacity=\"0.6\"/>")
            if !connection.label.isEmpty {
                let width = CGFloat(connection.label.count) * 5.6 + 12
                out.append("<rect x=\"\(n(g.handle.x - width / 2))\" y=\"\(n(g.handle.y - 8))\" width=\"\(n(width))\" height=\"16\" "
                           + "rx=\"8\" \(paint("fill", scene.palette.canvas)) \(paint("stroke", color)) stroke-opacity=\"0.6\"/>")
                out.append("<text x=\"\(n(g.handle.x))\" y=\"\(n(g.handle.y))\" text-anchor=\"middle\" dominant-baseline=\"central\" "
                           + "font-size=\"10\" font-weight=\"500\" \(paint("fill", color))>\(XMLText.escape(connection.label))</text>")
            }
        }
        return out
    }

    /// „rgb(…)“ für Attribute ohne eigenes paint().
    static func svgColor(_ hexValue: String) -> String {
        let c = RGBAColor(hex: hexValue) ?? RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        return "rgb(\(Int((c.red * 255).rounded())),\(Int((c.green * 255).rounded())),\(Int((c.blue * 255).rounded())))"
    }

    // MARK: - Zeilenumbruch wie in der App

    struct Line: Equatable {
        var text: String
        /// Grundlinie, gemessen von der Oberkante des Textes.
        var baseline: CGFloat
    }

    static func lineLayout(_ text: String, font: NSFont, width: CGFloat = NodeMetrics.maxTextWidth) -> [Line] {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let manager = NSLayoutManager()
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var lines: [Line] = []
        var glyph = 0
        let string = text as NSString
        while glyph < manager.numberOfGlyphs {
            var range = NSRange()
            let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &range)
            let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            let line = string.substring(with: characters).trimmingCharacters(in: .newlines)
            let baseline = fragment.minY + manager.location(forGlyphAt: glyph).y
            lines.append(Line(text: line, baseline: baseline))
            glyph = NSMaxRange(range)
        }
        if lines.isEmpty { lines = [Line(text: text, baseline: font.ascender)] }
        return lines
    }

    // MARK: - Hilfen

    /// Zahl mit höchstens einer Nachkommastelle, immer mit Punkt.
    static func n(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", Double(rounded))
    }

    /// `fill="rgb(…)"` bzw. `stroke="rgb(…)"`, bei Transparenz mit Deckkraft.
    private static func paint(_ attribute: String, _ hexValue: String) -> String {
        let c = RGBAColor(hex: hexValue) ?? RGBAColor(red: 0.5, green: 0.5, blue: 0.5)
        var s = "\(attribute)=\"rgb(\(Int((c.red * 255).rounded())),\(Int((c.green * 255).rounded())),\(Int((c.blue * 255).rounded())))\""
        if c.alpha < 1 { s += " \(attribute)-opacity=\"\(String(format: "%.2f", c.alpha))\"" }
        return s
    }

    private static func weight(_ w: NSFont.Weight) -> Int {
        if w == .bold { return 700 }
        if w == .semibold { return 600 }
        if w == .medium { return 500 }
        return 400
    }

    private static func fontFamily(_ font: Theme.Font) -> String {
        switch font {
        case .rounded: return "ui-rounded, 'SF Pro Rounded', -apple-system, BlinkMacSystemFont, 'Helvetica Neue', Arial, sans-serif"
        case .serif: return "ui-serif, 'New York', Georgia, 'Times New Roman', serif"
        case .monospaced: return "ui-monospace, 'SF Mono', Menlo, Consolas, monospace"
        case .system, .systemBold: return "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', Helvetica, Arial, sans-serif"
        }
    }
}
