import SwiftUI

/// Zoom und Verschiebung der Mindmap-Arbeitsfläche eines Fensters.
final class CanvasModel: ObservableObject {
    @Published var viewport = Viewport()

    /// Größe der Arbeitsfläche und Umriss der Map – werden von der Ansicht gemeldet.
    private(set) var viewSize: CGSize = .zero
    private(set) var mapBounds: CGRect = .zero
    /// Solange niemand selbst gezoomt oder verschoben hat, wird bei jeder Größenänderung neu eingepasst.
    /// (Beim Öffnen meldet das Fenster erst eine vorläufige, zu kleine Größe.)
    private var userAdjusted = false

    private var center: CGPoint {
        CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    func zoom(by factor: CGFloat, anchor: CGPoint? = nil) {
        userAdjusted = true
        viewport = viewport.zoomed(by: factor, anchor: anchor ?? center)
    }

    func zoomIn() { zoom(by: 1.25) }
    func zoomOut() { zoom(by: 0.8) }
    func actualSize() { zoom(by: 1 / viewport.zoom) }

    func zoomToFit() {
        userAdjusted = true
        viewport = .fitting(mapBounds, in: viewSize, maxFitZoom: 2)
    }

    func pan(by delta: CGSize) {
        userAdjusted = true
        viewport = viewport.panned(by: delta)
    }

    /// Verschiebt nur, wenn `rect` (Map-Koordinaten) nicht vollständig sichtbar ist.
    func reveal(_ rect: CGRect) {
        guard viewSize.width > 0 else { return }
        let moved = viewport.revealing(rect, in: viewSize)
        if moved != viewport { viewport = moved }
    }

    /// Meldet Fenstergröße und Map-Umriss. Ändert sich die Fenstergröße, wird die Map eingepasst
    /// (solange noch niemand selbst gezoomt hat) – sonst bleibt sie mittig.
    func update(size: CGSize, bounds: CGRect) {
        let oldSize = viewSize
        viewSize = size
        mapBounds = bounds
        guard size.width > 0, size.height > 0, size != oldSize else { return }
        if !userAdjusted || oldSize.width <= 0 {
            viewport = .fitting(bounds, in: size, maxFitZoom: 1)
        } else {
            viewport = viewport.panned(by: CGSize(width: (size.width - oldSize.width) / 2,
                                                  height: (size.height - oldSize.height) / 2))
        }
    }
}
