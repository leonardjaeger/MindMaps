import SwiftUI
import AppKit

/// Verkleinerte, nicht bedienbare Mindmap – für Vorschaubilder in der Bibliothek und für Quick Look.
struct MapThumbnailView: View {
    let root: Node
    let theme: Theme
    var dark = false
    var images: AssetImages = .empty
    var connections: [Connection] = []
    /// Layout und Zweige (M8).
    var style = MapStyle()
    /// Ausgewählter Knoten und hervorgehobene Knoten (Verlauf, M10).
    var selection: UUID?
    var marked: Set<UUID> = []
    /// Klick auf einen Knoten (Verlauf, M10) – `nil` = Klick daneben. Ohne: nicht bedienbar.
    var onSelect: ((UUID?) -> Void)?

    var body: some View {
        let metrics = NodeMetrics(theme: theme, style: style)
        let layout = MapLayoutEngine.layout(root: root, style: style) { node, depth in
            metrics.size(of: node, depth: depth)
        }
        let palette = theme.palette(dark: dark)
        let renderer = MapRenderer(root: root, layout: layout, theme: theme, palette: palette, metrics: metrics,
                                   images: images, connections: connections)
        Canvas { context, size in
            let bounds = layout.bounds.insetBy(dx: -24, dy: -24)
            let scale = min(size.width / bounds.width, size.height / bounds.height, 1.5)
            context.translateBy(x: size.width / 2 - bounds.midX * scale,
                                y: size.height / 2 - bounds.midY * scale)
            context.scaleBy(x: scale, y: scale)
            var state = MapRenderer.State(selection: selection, showHandle: false)
            state.matches = marked
            // Sehr klein (große Maps): Balken statt unlesbar kleinem Text – deutlich schneller (M12).
            state.zoom = scale
            renderer.draw(in: &context, state: state)
        }
        .background(Color(hex: palette.canvas))
        .overlay {
            if let onSelect {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            onSelect(Self.hit(location, size: proxy.size, layout: layout))
                        }
                }
            }
        }
    }

    /// Knoten unter einem Punkt der Vorschau (gleiche Umrechnung wie beim Zeichnen).
    static func hit(_ location: CGPoint, size: CGSize, layout: MindMapLayout) -> UUID? {
        let bounds = layout.bounds.insetBy(dx: -24, dy: -24)
        let scale = min(size.width / bounds.width, size.height / bounds.height, 1.5)
        guard scale > 0 else { return nil }
        let point = CGPoint(x: (location.x - size.width / 2) / scale + bounds.midX,
                            y: (location.y - size.height / 2) / scale + bounds.midY)
        return layout.order.last { layout.nodes[$0]?.frame.insetBy(dx: -4, dy: -4).contains(point) == true }
    }
}

/// Erzeugt das Vorschaubild (PNG), das in jeder `.mindmaps`-Datei unter `QuickLook/` mitgespeichert wird.
enum PreviewImage {
    static let size = CGSize(width: 1200, height: 800)

    @MainActor
    static func png(for data: MindMapDocumentData, assets: [String: Data] = [:]) -> Data? {
        let view = MapThumbnailView(root: data.root, theme: ThemeStore.theme(for: data),
                                    images: AssetImages(assets), connections: data.connections, style: data.style)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
