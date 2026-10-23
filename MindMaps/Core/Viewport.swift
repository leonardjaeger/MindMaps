import Foundation

/// Sichtbarer Ausschnitt der Mindmap: Zoomfaktor und Verschiebung.
///
/// Ein Punkt der Map erscheint in der Ansicht bei `punkt * zoom + offset`.
/// Reine Geometrie ohne SwiftUI, damit sie getestet werden kann.
struct Viewport: Equatable {
    static let minZoom: CGFloat = 0.2
    static let maxZoom: CGFloat = 4

    var zoom: CGFloat = 1
    var offset: CGPoint = .zero

    static func clampZoom(_ z: CGFloat) -> CGFloat {
        min(max(z, minZoom), maxZoom)
    }

    func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * zoom + offset.x, y: p.y * zoom + offset.y)
    }

    func toMap(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom)
    }

    func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin), size: CGSize(width: r.width * zoom, height: r.height * zoom))
    }

    /// Ausschnitt der Ansicht in Map-Koordinaten (z. B. der sichtbare Bereich).
    func toMap(_ r: CGRect) -> CGRect {
        CGRect(origin: toMap(r.origin), size: CGSize(width: r.width / zoom, height: r.height / zoom))
    }

    /// Zoomt um `factor`. Der Punkt `anchor` (Ansichtskoordinaten) bleibt dabei an seiner Stelle.
    func zoomed(by factor: CGFloat, anchor: CGPoint) -> Viewport {
        let newZoom = Self.clampZoom(zoom * factor)
        let mapAnchor = toMap(anchor)
        return Viewport(zoom: newZoom,
                        offset: CGPoint(x: anchor.x - mapAnchor.x * newZoom,
                                        y: anchor.y - mapAnchor.y * newZoom))
    }

    func panned(by delta: CGSize) -> Viewport {
        Viewport(zoom: zoom, offset: CGPoint(x: offset.x + delta.width, y: offset.y + delta.height))
    }

    /// Zeigt `bounds` (Map) mittig in einer Ansicht der Größe `size`.
    /// Vergrößert höchstens bis `maxFitZoom`, damit kleine Maps nicht riesig werden.
    static func fitting(_ bounds: CGRect, in size: CGSize,
                        padding: CGFloat = 40, maxFitZoom: CGFloat = 1) -> Viewport {
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else {
            return Viewport(zoom: 1, offset: CGPoint(x: size.width / 2, y: size.height / 2))
        }
        let availableWidth = max(size.width - 2 * padding, 1)
        let availableHeight = max(size.height - 2 * padding, 1)
        let z = clampZoom(min(availableWidth / bounds.width, availableHeight / bounds.height, maxFitZoom))
        return Viewport(zoom: z, offset: CGPoint(x: size.width / 2 - bounds.midX * z,
                                                 y: size.height / 2 - bounds.midY * z))
    }

    /// Verschiebt so wenig wie möglich, damit `rect` (Map) mit Rand `margin` sichtbar ist.
    func revealing(_ rect: CGRect, in size: CGSize, margin: CGFloat = 24) -> Viewport {
        let r = toView(rect)
        func shift(min lo: CGFloat, max hi: CGFloat, length: CGFloat) -> CGFloat {
            if hi - lo + 2 * margin > length { return length / 2 - (lo + hi) / 2 }
            if lo < margin { return margin - lo }
            if hi > length - margin { return length - margin - hi }
            return 0
        }
        let dx = shift(min: r.minX, max: r.maxX, length: size.width)
        let dy = shift(min: r.minY, max: r.maxY, length: size.height)
        return panned(by: CGSize(width: dx, height: dy))
    }
}
