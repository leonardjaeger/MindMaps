import SwiftUI
import AppKit

/// Fängt Scroll- und Pinch-Ereignisse über der Arbeitsfläche ab (SwiftUI bietet dafür keine Gesten).
///
/// - Zwei Finger / Mausrad: verschieben (mit ⌘: zoomen)
/// - Pinch auf dem Trackpad: zoomen
///
/// Mausklicks gehen unverändert an SwiftUI weiter.
struct ScrollZoomCatcher: NSViewRepresentable {
    /// Verschiebung, Position in der Ansicht, ⌘ gedrückt
    var onScroll: (CGSize, CGPoint, Bool) -> Void
    /// Zoomfaktor, Position in der Ansicht
    var onMagnify: (CGFloat, CGPoint) -> Void
    /// Rechtsklick (oder ⌃-Klick): Menü für diese Stelle, `nil` = keins (M7)
    var onRightClick: (CGPoint) -> NSMenu? = { _ in nil }

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
        view.onRightClick = onRightClick
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) {
        view.removeMonitor()
    }

    final class CatcherView: NSView {
        var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?
        var onRightClick: ((CGPoint) -> NSMenu?)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        /// Nie Ziel von Klicks – die bearbeitet SwiftUI.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                if event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                    guard let menu = self.onRightClick?(point) else { return event }
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                    return nil
                }
                if event.type == .leftMouseDown { return event }
                if event.type == .magnify {
                    self.onMagnify?(1 + event.magnification, point)
                } else {
                    var dx = event.scrollingDeltaX
                    var dy = event.scrollingDeltaY
                    if !event.hasPreciseScrollingDeltas {
                        dx *= 10
                        dy *= 10
                    }
                    self.onScroll?(CGSize(width: dx, height: dy), point, event.modifierFlags.contains(.command))
                }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
