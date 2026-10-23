import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Alles, was zum Zeichnen einer Mindmap außerhalb des Fensters nötig ist (helles Erscheinungsbild).
struct MapExportScene {
    let root: Node
    let theme: Theme
    let palette: ThemePalette
    let metrics: NodeMetrics
    let layout: MindMapLayout
    let tagCatalog: TagCatalog
    let images: AssetImages
    let connections: [Connection]

    init(data: MindMapDocumentData, assets: [String: Data] = [:], dark: Bool = false,
         tagCatalog: TagCatalog = TagStore.catalog) {
        let theme = ThemeStore.theme(for: data)
        let metrics = NodeMetrics(theme: theme, style: data.style)
        self.root = data.root
        self.theme = theme
        self.palette = theme.palette(dark: dark)
        self.metrics = metrics
        self.tagCatalog = tagCatalog
        self.images = AssetImages(assets)
        self.connections = data.connections
        self.layout = MapLayoutEngine.layout(root: data.root, style: data.style) { node, depth in
            metrics.size(of: node, depth: depth)
        }
    }

    var renderer: MapRenderer {
        MapRenderer(root: root, layout: layout, theme: theme, palette: palette, metrics: metrics, tagCatalog: tagCatalog,
                    images: images, connections: connections)
    }

    /// Fläche der Map inklusive der Zähler an eingeklappten Knoten, plus Rand.
    func contentBounds(padding: CGFloat) -> CGRect {
        var bounds = layout.bounds
        let renderer = self.renderer
        for node in layout.nodes.values where renderer.isCollapsed(node.id) {
            bounds = bounds.union(renderer.badgeRect(for: node))
        }
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    /// Flächen mit Inhalt (Knoten und Zweige) – leere PDF-Seiten fallen damit weg.
    func occupiedRects() -> [CGRect] {
        var rects: [CGRect] = []
        for node in layout.nodes.values {
            rects.append(node.frame.insetBy(dx: -4, dy: -4))
            if let pid = node.parentID, let parent = layout.nodes[pid] {
                let a = CGPoint(x: parent.frame.midX, y: parent.frame.midY)
                let b = CGPoint(x: node.frame.midX, y: node.frame.midY)
                rects.append(CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                    width: abs(a.x - b.x) + 1, height: abs(a.y - b.y) + 1))
            }
        }
        return rects
    }
}

/// Ein Ausschnitt der Map auf einer Bild- oder PDF-Seite.
struct MapPageView: View {
    let scene: MapExportScene
    /// Ausschnitt in Map-Koordinaten.
    let region: CGRect
    let scale: CGFloat
    /// Abstand des Ausschnitts vom Seitenrand.
    let margin: CGFloat
    let background: Color?
    var footer: String?

    var body: some View {
        let renderer = scene.renderer
        Canvas { context, size in
            if let background {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))
            }
            var map = context
            map.translateBy(x: margin, y: margin)
            map.clip(to: Path(CGRect(x: 0, y: 0, width: region.width * scale, height: region.height * scale)))
            map.scaleBy(x: scale, y: scale)
            map.translateBy(x: -region.minX, y: -region.minY)
            renderer.draw(in: &map, state: MapRenderer.State(showHandle: false))

            if let footer {
                let text = Text(footer).font(.system(size: 8)).foregroundStyle(Color.gray)
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height - margin / 2), anchor: .center)
            }
        }
    }
}

/// Wie der PDF-Export die Seiten aufteilt.
enum PDFPaging: String, CaseIterable, Identifiable {
    case a4, singlePage
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a4: return L("A4-Seiten (zum Drucken)")
        case .singlePage: return L("Eine Seite (ganze Mindmap)")
        }
    }
}

struct ExportOptions: Equatable {
    var transparent = false
    var pngScale: CGFloat = 2
    var paging: PDFPaging = .a4
}

extension ExportFormat {
    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .opml: return UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
        case .plainText: return .plainText
        case .rtf: return .rtf
        case .textBundle: return UTType(filenameExtension: "textbundle", conformingTo: .package) ?? .package
        case .freeMind: return UTType(filenameExtension: "mm", conformingTo: .xml) ?? .xml
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return .svg
        }
    }
}

/// Bild-Exporte (PNG, PDF, SVG) und die gemeinsame Einstiegsstelle für alle Formate.
@MainActor
enum MapImageExporter {
    enum ExportError: LocalizedError {
        case renderFailed
        var errorDescription: String? { L("Das Bild der Mindmap ließ sich nicht erzeugen.") }
    }

    static let imagePadding: CGFloat = 40
    /// Obergrenze für PNG-Kantenlänge in Pixeln.
    static let maximumPixels: CGFloat = 16_000

    /// Datei oder Paket im gewünschten Format.
    static func fileWrapper(for data: MindMapDocumentData, assets: [String: Data] = [:], format: ExportFormat,
                            options: ExportOptions, title: String) throws -> FileWrapper {
        if let text = TextExporter.fileWrapper(for: data, format: format) { return text }
        switch format {
        case .png:
            return FileWrapper(regularFileWithContents: try png(data, assets: assets, scale: options.pngScale,
                                                                transparent: options.transparent))
        case .pdf:
            return FileWrapper(regularFileWithContents: try pdf(data, assets: assets, paging: options.paging,
                                                                transparent: options.transparent, title: title))
        case .svg:
            return FileWrapper(regularFileWithContents: Data(SVGExporter.svg(for: data, assets: assets).utf8))
        default:
            throw ExportError.renderFailed
        }
    }

    // MARK: - PNG

    /// Pixelgröße des PNG (für die Anzeige im Dialog).
    static func pngPixelSize(_ data: MindMapDocumentData, scale: CGFloat) -> CGSize {
        let bounds = MapExportScene(data: data).contentBounds(padding: imagePadding)
        let s = effectivePNGScale(bounds, scale)
        return CGSize(width: (bounds.width * s).rounded(), height: (bounds.height * s).rounded())
    }

    private static func effectivePNGScale(_ bounds: CGRect, _ scale: CGFloat) -> CGFloat {
        min(scale, maximumPixels / max(bounds.width, bounds.height, 1))
    }

    static func png(_ data: MindMapDocumentData, assets: [String: Data] = [:], scale: CGFloat,
                    transparent: Bool) throws -> Data {
        let scene = MapExportScene(data: data, assets: assets)
        let bounds = scene.contentBounds(padding: imagePadding)
        let view = MapPageView(scene: scene, region: bounds, scale: 1, margin: 0,
                               background: transparent ? nil : Color(hex: scene.palette.canvas))
            .frame(width: bounds.width, height: bounds.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = effectivePNGScale(bounds, scale)
        renderer.isOpaque = !transparent
        guard let image = renderer.cgImage else { throw ExportError.renderFailed }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = bounds.size // 72 dpi × Faktor: Programme zeigen es in „Originalgröße“ richtig an
        guard let png = rep.representation(using: .png, properties: [:]) else { throw ExportError.renderFailed }
        return png
    }

    // MARK: - PDF

    static func tiling(_ data: MindMapDocumentData, paging: PDFPaging) -> PageTiling {
        let scene = MapExportScene(data: data)
        switch paging {
        case .singlePage:
            return PageTiling.singlePage(content: scene.contentBounds(padding: imagePadding))
        case .a4:
            return PageTiling.a4(content: scene.contentBounds(padding: 8), occupied: scene.occupiedRects())
        }
    }

    static func pdf(_ data: MindMapDocumentData, assets: [String: Data] = [:], paging: PDFPaging,
                    transparent: Bool, title: String, dark: Bool = false) throws -> Data {
        let scene = MapExportScene(data: data, assets: assets, dark: dark)
        let pages = Self.tiling(data, paging: paging)
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pages.pageSize)
        let info = [kCGPDFContextCreator as String: "MindMaps",
                    kCGPDFContextTitle as String: title] as CFDictionary
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, info) else {
            throw ExportError.renderFailed
        }
        let background = transparent ? nil : Color(hex: scene.palette.canvas)
        let count = pages.tiles.count
        for (index, tile) in pages.tiles.enumerated() {
            let footer = count > 1
                ? L("%@ · Seite %@ von %@ · Reihe %@, Spalte %@", title, "\(index + 1)", "\(count)", "\(tile.row + 1)", "\(tile.column + 1)")
                : nil
            let page = MapPageView(scene: scene, region: tile.rect, scale: pages.scale, margin: pages.margin,
                                   background: background, footer: footer)
                .frame(width: pages.pageSize.width, height: pages.pageSize.height)
            let renderer = ImageRenderer(content: page)
            // Vektorgrafik; falls etwas gerastert werden muss, dann in hoher Auflösung.
            renderer.render(rasterizationScale: 4) { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return output as Data
    }
}
