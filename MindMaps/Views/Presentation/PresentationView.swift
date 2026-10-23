import SwiftUI
import AppKit

/// Kamerafahrt zwischen zwei Ausschnitten (weich, ohne unscharfe Vergrößerung – die Map wird
/// in jedem Bild neu gezeichnet).
struct CameraMove: Equatable {
    var from = Viewport()
    var to = Viewport()
    var start = Date.distantPast
    static let duration: TimeInterval = 0.6

    func viewport(at date: Date) -> Viewport {
        let t = min(max(date.timeIntervalSince(start) / Self.duration, 0), 1)
        let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)   // easeInOut
        return Viewport(zoom: from.zoom + (to.zoom - from.zoom) * e,
                        offset: CGPoint(x: from.offset.x + (to.offset.x - from.offset.x) * e,
                                        y: from.offset.y + (to.offset.y - from.offset.y) * e))
    }

    func isRunning(at date: Date) -> Bool {
        date.timeIntervalSince(start) < Self.duration
    }
}

/// Präsentationsmodus (⌥ ⌘ P): Vollbild, Zweig für Zweig mit den Pfeiltasten.
///
/// | Taste | Wirkung |
/// |---|---|
/// | → ↓ Leertaste ↩ | nächster Schritt |
/// | ← ↑ | zurück |
/// | N | Notizen ein/aus |
/// | Esc | beenden |
struct PresentationView: View {
    let data: MindMapDocumentData
    let images: AssetImages
    let onClose: () -> Void

    @State private var step = 0
    @State private var camera = CameraMove()
    @State private var viewSize: CGSize = .zero
    @State private var showNotes = true
    @State private var settled = 0
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme
    /// „Bewegung reduzieren“ in macOS: springen statt fahren (M12).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TagStore.key) private var tagJSON = ""

    private var theme: Theme { ThemeStore.theme(for: data) }

    var body: some View {
        let theme = self.theme
        let metrics = NodeMetrics(theme: theme, style: data.style)
        let layout = MapLayoutEngine.layout(root: data.root, style: data.style) { node, depth in
            metrics.size(of: node, depth: depth)
        }
        let palette = theme.palette(dark: colorScheme == .dark)
        let plan = PresentationPlan(root: data.root)
        let current = plan.steps[min(step, plan.steps.count - 1)]
        let renderer = MapRenderer(root: data.root, layout: layout, theme: theme, palette: palette, metrics: metrics,
                                   tagCatalog: TagStore.decode(tagJSON), images: images, connections: data.connections)
        var state = MapRenderer.State(selection: current.isOverview ? nil : current.focus, showHandle: false)
        state.hidden = Set(layout.order).subtracting(current.revealed)
        let drawState = state

        return GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: nil, paused: settled < 0 || !camera.isRunning(at: Date()))) { timeline in
                let viewport = camera.viewport(at: timeline.date)
                Canvas { context, size in
                    context.translateBy(x: viewport.offset.x, y: viewport.offset.y)
                    context.scaleBy(x: viewport.zoom, y: viewport.zoom)
                    var frameState = drawState
                    frameState.visibleRect = viewport.toMap(CGRect(origin: .zero, size: size))
                    renderer.draw(in: &context, state: frameState)
                }
            }
            .onAppear {
                viewSize = proxy.size
                camera = CameraMove(from: target(for: current, layout: layout, size: proxy.size),
                                    to: target(for: current, layout: layout, size: proxy.size), start: .distantPast)
            }
            .onChange(of: proxy.size) { _, size in
                viewSize = size
                let fit = target(for: current, layout: layout, size: size)
                camera = CameraMove(from: fit, to: fit, start: .distantPast)
            }
            .onChange(of: step) { _, newStep in
                let now = Date()
                let next = plan.steps[min(newStep, plan.steps.count - 1)]
                let goal = target(for: next, layout: layout, size: viewSize)
                camera = reduceMotion
                    ? CameraMove(from: goal, to: goal, start: .distantPast)
                    : CameraMove(from: camera.viewport(at: now), to: goal, start: now)
                // Nach der Fahrt einmal neu zeichnen, damit die Zeitleiste anhält.
                DispatchQueue.main.asyncAfter(deadline: .now() + CameraMove.duration + 0.05) { settled += 1 }
            }
        }
        .background(Color(hex: palette.canvas))
        .overlay(alignment: .bottom) { notePanel(current) }
        .overlay(alignment: .topTrailing) { hint(plan) }
        .contentShape(Rectangle())
        .onTapGesture { advance(1, plan) }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.rightArrow, .downArrow, .space, .return]) { _ in
            advance(1, plan)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .upArrow]) { _ in
            advance(-1, plan)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "nN")) { _ in
            showNotes.toggle()
            return .handled
        }
        .onExitCommand(perform: onClose)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    private func advance(_ delta: Int, _ plan: PresentationPlan) {
        step = min(max(step + delta, 0), plan.steps.count - 1)
    }

    /// Ausschnitt für einen Schritt: aktueller Hauptast (mit Hauptknoten) bzw. alles.
    private func target(for step: PresentationPlan.Step, layout: MindMapLayout, size: CGSize) -> Viewport {
        let frames = step.camera.compactMap { layout.nodes[$0]?.frame }
        guard let first = frames.first else { return Viewport() }
        let bounds = frames.dropFirst().reduce(first) { $0.union($1) }
        let bottomSpace: CGFloat = showNotes ? 120 : 0
        let area = CGSize(width: size.width, height: max(size.height - bottomSpace, 100))
        return Viewport.fitting(bounds, in: area, padding: 80, maxFitZoom: 2.2)
    }

    @ViewBuilder
    private func notePanel(_ step: PresentationPlan.Step) -> some View {
        if showNotes, !step.isOverview, let node = data.root.node(withID: step.focus), !node.note.isEmpty {
            Text(NoteMarkup.plainText(node.note))
                .font(.system(size: 17))
                .lineLimit(5)
                .frame(maxWidth: 820, alignment: .leading)
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.bottom, 24)
                .padding(.horizontal, 40)
                .allowsHitTesting(false)
        }
    }

    private func hint(_ plan: PresentationPlan) -> some View {
        Text(L("%@ / %@   ← →  blättern · N  Notizen · Esc  beenden", "\(step + 1)", "\(plan.steps.count)"))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(16)
            .allowsHitTesting(false)
    }
}
