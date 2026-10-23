import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Die Mindmap-Arbeitsfläche. Berechnet das Layout und gibt es an `MapSurface` weiter,
/// damit Zoomen und Verschieben das Layout nicht jedes Mal neu berechnen.
struct MapCanvasView: View {
    let root: Node
    let theme: Theme
    @Binding var selection: UUID?
    @Binding var editingNode: UUID?
    let canvas: CanvasModel
    var isFocused: FocusState<Bool>.Binding
    let actions: DocumentActions
    /// Meldet den Text beim Tippen (für die Outline); `nil` = Bearbeiten beendet.
    let onLiveText: (UUID, String?) -> Void
    /// Hervorheben und Suchtreffer (M6).
    var marks = MapMarks()
    /// Bilder, Verbindungen, Menüs, Links (M7).
    var interaction = MapInteraction()
    /// Layout und Zweige (M8).
    var mapStyle = MapStyle()

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TagStore.key) private var tagJSON = ""

    var body: some View {
        let metrics = NodeMetrics(theme: theme, style: mapStyle)
        let layout = MapLayoutEngine.layout(root: root, style: mapStyle) { node, depth in
            metrics.size(of: node, depth: depth)
        }
        let palette = theme.palette(dark: colorScheme == .dark)
        // Einmal pro Änderung am Dokument – nicht bei jedem Bild beim Verschieben und Zoomen (M12).
        let renderer = MapRenderer(root: root, layout: layout, theme: theme, palette: palette, metrics: metrics,
                                   tagCatalog: TagStore.decode(tagJSON), images: interaction.images,
                                   connections: interaction.connections)
        MapSurface(root: root, layout: layout, baseRenderer: renderer, theme: theme,
                   palette: palette, metrics: metrics,
                   selection: $selection, editingNode: $editingNode,
                   canvas: canvas, isFocused: isFocused, actions: actions,
                   onLiveText: onLiveText, marks: marks, interaction: interaction)
    }
}

/// Was die Map zusätzlich zeigt: blasse Knoten (Hervorheben, Fokus), Suchtreffer.
struct MapMarks: Equatable {
    var dimmed: Set<UUID> = []
    var matches: Set<UUID> = []
    var currentMatch: UUID?
}

/// Verbindungen, Bilder, Links und Kontextmenüs der Map (M7).
struct MapInteraction {
    var images: AssetImages = .empty
    var connections: [Connection] = []
    var selectedConnection: Binding<UUID?> = .constant(nil)
    /// Gesetzt: Der nächste Klick auf einen Knoten legt eine Verbindung von diesem Knoten an.
    var connectFrom: Binding<UUID?> = .constant(nil)
    var nodeMenu: (UUID) -> [MenuEntry] = { _ in [] }
    var connectionMenu: (UUID) -> [MenuEntry] = { _ in [] }
    var openLink: (String) -> Void = { _ in }
    var editConnectionLabel: (UUID) -> Void = { _ in }
    /// Rechtsklick auf die freie Fläche: Layout, Positionen (M8).
    var canvasMenu: () -> [MenuEntry] = { [] }
    /// ⌘ C in der Map: Stil des Knotens merken (zum Einsetzen mit ⌘ R).
    var copyStyle: (UUID) -> Void = { _ in }
}

/// Notiz-Popover an einem Knoten der Map.
struct NotePopoverTarget: Identifiable, Equatable {
    let id: UUID
    let rect: CGRect
}

/// Zeichnet die Map und verarbeitet Maus, Trackpad und Tastatur.
///
/// | Eingabe | Wirkung |
/// |---|---|
/// | Klick | Knoten auswählen (leere Fläche: Auswahl aufheben) |
/// | Doppelklick, Leertaste | Knoten bearbeiten |
/// | Tab / ↩ / ⌫ | Unterknoten / Knoten danach / löschen |
/// | Pfeiltasten | Auswahl bewegen |
/// | „+“-Griff | Unterknoten anhängen |
/// | Zähler neben eingeklapptem Knoten | aufklappen |
/// | Knoten ziehen | auf einen anderen Knoten: umhängen (Ziel gestrichelt markiert), sonst frei verschieben |
/// | Kästchen / Fortschrittskreis | abhaken |
/// | Blatt-Symbol | Notiz im Popover |
/// | Link-Symbol | Link öffnen |
/// | ⌥ + Knoten ziehen | Querverbindung zu einem anderen Knoten |
/// | Verbindung anklicken, Griff ziehen | auswählen, Bogen ändern (Doppelklick: Beschriftung) |
/// | Griff unten rechts im Bild | Bildgröße ändern |
/// | Bild auf einen Knoten ziehen | Bild einfügen |
/// | Link auf einen Knoten ziehen | Link setzen (z. B. PDF-Stelle aus MintMarkPDF, 1.3) |
/// | Rechtsklick | Kontextmenü (Knoten, Verbindung oder freie Fläche) |
/// | ⌘ C / ⌘ R | Stil des Knotens kopieren / auf den ausgewählten Knoten übertragen |
/// | Fläche ziehen, zwei Finger | verschieben |
/// | Pinch, ⌘ + Scrollen | zoomen |
struct MapSurface: View {
    let root: Node
    let layout: MindMapLayout
    /// Fertig vorbereiteter Zeichner (merkt sich Aussehen und Aufteilung der Knoten).
    let baseRenderer: MapRenderer
    let theme: Theme
    let palette: ThemePalette
    let metrics: NodeMetrics
    @Binding var selection: UUID?
    @Binding var editingNode: UUID?
    @ObservedObject var canvas: CanvasModel
    var isFocused: FocusState<Bool>.Binding
    let actions: DocumentActions
    let onLiveText: (UUID, String?) -> Void
    let marks: MapMarks
    let interaction: MapInteraction

    @State private var drag: DragMode? = nil
    @State private var notePopover: NotePopoverTarget?
    /// VoiceOver an? Dann bekommt jeder sichtbare Knoten ein eigenes Element (M12).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private enum DragMode {
        case pan(last: CGSize)
        case node(id: UUID, offset: CGSize, target: UUID?)
        /// ⌥ + Ziehen: neue Querverbindung
        case connect(from: UUID, point: CGPoint, target: UUID?)
        /// Griff einer Verbindung ziehen
        case bend(id: UUID, start: CGSize, current: CGSize)
        /// Bildgröße ändern (Vorschau als Rahmen, übernommen beim Loslassen)
        case resize(id: UUID, startWidth: Double, width: Double)
    }

    private var renderer: MapRenderer {
        var renderer = baseRenderer
        // Während des Biegens die Verbindung live zeigen.
        if case .bend(let id, _, let current)? = drag,
           let index = renderer.connections.firstIndex(where: { $0.id == id }) {
            renderer.connections[index].bendX = Double(current.width)
            renderer.connections[index].bendY = Double(current.height)
        }
        return renderer
    }

    private var selectedConnection: UUID? {
        get { interaction.selectedConnection.wrappedValue }
        nonmutating set { interaction.selectedConnection.wrappedValue = newValue }
    }

    private var connectFrom: UUID? {
        get { interaction.connectFrom.wrappedValue }
        nonmutating set { interaction.connectFrom.wrappedValue = newValue }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                canvasLayer
                    .frame(width: proxy.size.width, height: proxy.size.height)

                if let id = editingNode, let placed = layout.nodes[id], let model = root.node(withID: id) {
                    inlineEditor(for: placed, model: model)
                        .id(id)
                }
            }
            .popover(item: $notePopover, attachmentAnchor: .rect(.rect(notePopover?.rect ?? .zero)),
                     arrowEdge: .bottom) { target in
                NotePopover(node: root.node(withID: target.id), actions: actions)
            }
            .onAppear { canvas.update(size: proxy.size, bounds: layout.bounds) }
            .onChange(of: proxy.size) { _, size in canvas.update(size: size, bounds: layout.bounds) }
            .onChange(of: layout.bounds) { _, bounds in canvas.update(size: proxy.size, bounds: bounds) }
        }
        .clipped()
        .onChange(of: selection) { _, id in
            reveal(id)
            announce(id)
        }
        .onChange(of: editingNode) { _, id in reveal(id) }
        .onChange(of: layout) { _, _ in reveal(editingNode ?? selection) }
    }

    // MARK: - Zeichenfläche

    private var canvasLayer: some View {
        let viewport = canvas.viewport
        let renderer = self.renderer
        var state = MapRenderer.State(selection: selection, editing: editingNode,
                                      showHandle: editingNode == nil && drag == nil)
        state.dimmed = marks.dimmed
        state.matches = marks.matches
        state.currentMatch = marks.currentMatch
        state.selectedConnection = selectedConnection
        if case .node(let id, let offset, let target)? = drag {
            state.dragging = id
            state.dragOffset = offset
            state.dropTarget = target
        }
        if case .connect(let from, let point, let target)? = drag {
            state.connectionDraft = (from, point, target)
        }
        let drawState = state
        // Neue Bildgröße als gestrichelter Rahmen, solange gezogen wird.
        var resizePreview: CGRect?
        if case .resize(let id, _, let width)? = drag, let placed = layout.nodes[id],
           let image = root.node(withID: id)?.image, let rect = renderer.contentLayout(for: placed)?.imageRect {
            let size = image.resized(toWidth: width)
            resizePreview = CGRect(x: rect.minX, y: rect.minY, width: CGFloat(size.width), height: CGFloat(size.height))
        }
        let preview = resizePreview

        return Canvas { context, size in
            context.translateBy(x: viewport.offset.x, y: viewport.offset.y)
            context.scaleBy(x: viewport.zoom, y: viewport.zoom)
            // Nur zeichnen, was im Fenster zu sehen ist (M12: große Maps bleiben flüssig).
            var frameState = drawState
            frameState.visibleRect = viewport.toMap(CGRect(origin: .zero, size: size))
            frameState.zoom = viewport.zoom
            renderer.draw(in: &context, state: frameState)
            if let preview {
                context.stroke(Path(roundedRect: preview, cornerRadius: 6), with: .color(.accentColor),
                               style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .background(Color(hex: palette.canvas))
        .background(ScrollZoomCatcher(
            onScroll: { delta, point, zoomModifier in
                if zoomModifier {
                    canvas.zoom(by: CGFloat(exp(Double(delta.height) * 0.01)), anchor: point)
                } else {
                    canvas.pan(by: delta)
                }
            },
            onMagnify: { factor, point in
                canvas.zoom(by: factor, anchor: point)
            },
            onRightClick: { point in contextMenu(at: point) }))
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .image, .url, .utf8PlainText, .plainText], isTargeted: nil) { providers, location in
            handleDrop(providers, at: location)
        }
        .gesture(dragGesture)
        .simultaneousGesture(SpatialTapGesture().onEnded { value in
            handleClick(at: value.location)
        })
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused(isFocused)
        // VoiceOver (M12): die Map als Gruppe, jeder sichtbare Knoten als eigenes Element.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Mindmap"))
        .accessibilityHint(L("Pfeiltasten wählen Knoten, Tab legt einen Unterknoten an, Leertaste bearbeitet."))
        .accessibilityChildren {
            if voiceOver { accessibilityNodes }
        }
        .onKeyPress(keys: [.tab, .return, .space,
                           .upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            handleKey(press)
        }
        // ⌘ C in der Map: Stil des ausgewählten Knotens kopieren (einsetzen mit ⌘ R).
        // Der Text des Knotens kommt zusätzlich in die Zwischenablage.
        .onCopyCommand { copyCommand() }
        // ⌫ kommt auf dem Mac als Lösch-Befehl an, nicht als Tastendruck.
        .onDeleteCommand {
            if let connection = selectedConnection {
                actions.removeConnection(connection)
                selectedConnection = nil
            } else {
                deleteSelection()
            }
        }
        // Esc: Verbinden abbrechen, Verbindung abwählen.
        .onExitCommand {
            connectFrom = nil
            selectedConnection = nil
        }
        // ⌘ . auch direkt in der Map (falls die Arbeitsfläche die Taste vor dem Menü bekommt).
        .onKeyPress(characters: CharacterSet(charactersIn: "."), phases: .down) { press in
            guard press.modifiers.contains(.command), editingNode == nil,
                  let id = selection, root.canToggleCollapse(id) else { return .ignored }
            actions.toggleCollapsed(id)
            return .handled
        }
    }

    // MARK: - VoiceOver (M12)

    /// Unsichtbare Elemente an den Stellen der sichtbaren Knoten, in Lesereihenfolge.
    private var accessibilityNodes: some View {
        let viewport = canvas.viewport
        let size = canvas.viewSize
        let visible = viewport.toMap(CGRect(origin: .zero, size: size))
        let ids = layout.order.filter { id in
            guard let placed = layout.nodes[id] else { return false }
            return id == selection || placed.frame.intersects(visible)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(ids, id: \.self) { id in
                if let placed = layout.nodes[id], let node = baseRenderer.model(id) {
                    let rect = viewport.toView(placed.frame)
                    Color.clear
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityElement()
                        .accessibilityLabel(NodeSpeech.label(node.text))
                        .accessibilityValue(NodeSpeech.details(NodeSpeech.facts(of: node, depth: placed.depth)))
                        .accessibilityAddTraits(selection == id ? [.isButton, .isSelected] : [.isButton])
                        .accessibilityAction {
                            selection = id
                            isFocused.wrappedValue = true
                        }
                        .accessibilityActions {
                            Button(L("Text bearbeiten")) {
                                selection = id
                                editingNode = id
                            }
                            Button(L("Unterknoten hinzufügen")) { addChild(to: id) }
                            if node.task != nil || node.hasTaskDescendants {
                                Button(node.taskStatus == .done ? L("Wieder öffnen") : L("Abhaken")) {
                                    actions.toggleDone(id)
                                }
                            }
                            if placed.depth > 0 && !node.children.isEmpty {
                                Button(node.isCollapsed ? L("Aufklappen") : L("Einklappen")) {
                                    actions.toggleCollapsed(id)
                                }
                            }
                        }
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Sagt den neu gewählten Knoten an, wenn VoiceOver läuft und die Map den Fokus hat.
    private func announce(_ id: UUID?) {
        guard voiceOver, isFocused.wrappedValue, editingNode == nil, let id,
              let placed = layout.nodes[id], let node = baseRenderer.model(id) else { return }
        AccessibilityNotification.Announcement(NodeSpeech.sentence(for: node, depth: placed.depth)).post()
    }

    // MARK: - Textfeld zum Bearbeiten

    private func inlineEditor(for placed: LayoutNode, model: Node) -> some View {
        let viewport = canvas.viewport
        let rect = viewport.toView(placed.frame)
        let look = renderer.appearance(for: placed)
        let pad = metrics.padding(depth: placed.depth, shape: look?.shape ?? .rounded)
        let corner = 8 * viewport.zoom
        let text = model.text
        return InlineNodeEditor(
            text: text,
            font: metrics.font(for: model, depth: placed.depth, scale: viewport.zoom),
            textColor: Color(hex: look?.text ?? palette.nodeText),
            onLiveChange: { draft in onLiveText(placed.id, draft) },
            onFinish: { newText in finishEditing(placed.id, text: newText) },
            onCancel: {
                onLiveText(placed.id, nil)
                editingNode = nil
                isFocused.wrappedValue = true
            })
            .padding(.horizontal, pad.width * viewport.zoom)
            .frame(width: max(rect.width, 150 * viewport.zoom), height: rect.height)
            .background(RoundedRectangle(cornerRadius: corner)
                .fill(Color(hex: look?.fill ?? palette.canvas)))
            .overlay(RoundedRectangle(cornerRadius: corner)
                .stroke(Color.accentColor, lineWidth: 2))
            .position(x: rect.midX, y: rect.midY)
    }

    private func finishEditing(_ id: UUID, text: String) {
        actions.setText(text, of: id)
        onLiveText(id, nil)
        if editingNode == id { editingNode = nil }
        isFocused.wrappedValue = true
    }

    // MARK: - Maus

    private func hitNode(_ point: CGPoint) -> UUID? {
        layout.order.last { layout.nodes[$0]?.frame.insetBy(dx: -4, dy: -4).contains(point) == true }
    }

    private func handleClick(at location: CGPoint) {
        isFocused.wrappedValue = true
        if editingNode != nil { editingNode = nil }
        let point = canvas.viewport.toMap(location)

        // Verbinden-Modus (Kontextmenü „Verbindung zu …“): Klick auf das Ziel.
        if let from = connectFrom {
            connectFrom = nil
            if let target = hitNode(point), target != from {
                selectedConnection = actions.connect(from, to: target)
                selection = nil
            }
            return
        }
        // Querverbindung: Griff oder Linie (Knoten haben Vorrang).
        if hitNode(point) == nil, let connection = renderer.connection(at: point) {
            selectedConnection = connection
            selection = nil
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { interaction.editConnectionLabel(connection) }
            return
        }
        selectedConnection = nil

        if let selected = selection, let placed = layout.nodes[selected],
           renderer.handleRect(for: placed, zoom: canvas.viewport.zoom).insetBy(dx: -3, dy: -3).contains(point) {
            addChild(to: selected)
            return
        }
        // Einklapp-Knopf „−“ am ausgewählten Knoten: einklappen.
        if let selected = selection, let placed = layout.nodes[selected],
           renderer.hasFoldControl(selected), !renderer.isCollapsed(selected),
           renderer.badgeRect(for: placed).insetBy(dx: -3, dy: -3).contains(point) {
            actions.toggleCollapsed(selected)
            return
        }
        // Zähler neben eingeklappten Knoten: aufklappen.
        if let collapsed = layout.order.last(where: { id in
            guard renderer.isCollapsed(id), let placed = layout.nodes[id] else { return false }
            return renderer.badgeRect(for: placed).insetBy(dx: -3, dy: -3).contains(point)
        }) {
            selection = collapsed
            actions.toggleCollapsed(collapsed)
            return
        }
        guard let id = hitNode(point) else {
            selection = nil
            return
        }
        // Kästchen: abhaken. Blatt-Symbol: Notiz öffnen.
        if let placed = layout.nodes[id], let content = renderer.contentLayout(for: placed) {
            if let box = content.leadingRect, box.insetBy(dx: -4, dy: -4).contains(point) {
                selection = id
                actions.toggleDone(id)
                return
            }
            if let note = content.noteRect, note.insetBy(dx: -4, dy: -4).contains(point) {
                selection = id
                notePopover = NotePopoverTarget(id: id, rect: canvas.viewport.toView(note))
                return
            }
            if let link = content.linkRect, link.insetBy(dx: -4, dy: -4).contains(point),
               let target = root.node(withID: id)?.link, !target.isEmpty {
                selection = id
                interaction.openLink(target)
                return
            }
        }
        selection = id
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            editingNode = id
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let viewport = canvas.viewport
                if drag == nil { drag = startDrag(at: viewport.toMap(value.startLocation)) }
                let point = viewport.toMap(value.location)
                switch drag {
                case .pan(let last)?:
                    canvas.pan(by: CGSize(width: value.translation.width - last.width,
                                          height: value.translation.height - last.height))
                    drag = .pan(last: value.translation)
                case .node(let id, _, _)?:
                    let target = hitNode(point).flatMap { candidate in
                        root.canMove(id, toParent: candidate) ? candidate : nil
                    }
                    drag = .node(id: id,
                                 offset: CGSize(width: value.translation.width / viewport.zoom,
                                                height: value.translation.height / viewport.zoom),
                                 target: target)
                case .connect(let from, _, _)?:
                    let target = hitNode(point).flatMap { $0 == from ? nil : $0 }
                    drag = .connect(from: from, point: point, target: target)
                case .bend(let id, let start, _)?:
                    drag = .bend(id: id, start: start,
                                 current: CGSize(width: start.width + value.translation.width / viewport.zoom,
                                                 height: start.height + value.translation.height / viewport.zoom))
                case .resize(let id, let startWidth, _)?:
                    let width = startWidth + Double(value.translation.width / viewport.zoom)
                    drag = .resize(id: id, startWidth: startWidth,
                                   width: min(max(width, NodeImage.minWidth), NodeImage.maxWidth))
                case nil:
                    break
                }
            }
            .onEnded { _ in
                switch drag {
                case .node(let id, _, let target?)?:
                    actions.move(id, to: target)
                    selection = id
                case .node(let id, let offset, nil)?:
                    // Kein Ziel: Knoten (samt Unterknoten) von Hand verschieben (M8).
                    actions.offsetNode(id, by: offset)
                    selection = id
                case .connect(let from, _, let target?)?:
                    selectedConnection = actions.connect(from, to: target)
                    selection = nil
                case .bend(let id, _, let current)?:
                    actions.setConnectionBend(current, of: id)
                case .resize(let id, _, let width)?:
                    actions.resizeImage(of: id, toWidth: width)
                default:
                    break
                }
                drag = nil
            }
    }

    /// Was ein Ziehen an dieser Stelle bewirkt.
    private func startDrag(at point: CGPoint) -> DragMode {
        let renderer = self.renderer
        // Griff einer ausgewählten Verbindung: biegen.
        if let id = selectedConnection, let connection = interaction.connections.first(where: { $0.id == id }),
           let geometry = renderer.geometry(for: connection),
           hypot(geometry.handle.x - point.x, geometry.handle.y - point.y) < 12 {
            let start = CGSize(width: geometry.handle.x - Self.straightMid(renderer, connection).x,
                               height: geometry.handle.y - Self.straightMid(renderer, connection).y)
            return .bend(id: id, start: start, current: start)
        }
        // Größen-Griff des Bildes am ausgewählten Knoten.
        if let id = selection, let placed = layout.nodes[id], let content = renderer.contentLayout(for: placed),
           let imageRect = content.imageRect, let image = root.node(withID: id)?.image,
           MapRenderer.resizeHandle(for: imageRect).insetBy(dx: -4, dy: -4).contains(point) {
            return .resize(id: id, startWidth: image.width, width: image.width)
        }
        guard editingNode == nil, let id = hitNode(point) else { return .pan(last: .zero) }
        // ⌥ + Ziehen: Querverbindung.
        if NSEvent.modifierFlags.contains(.option) {
            selectedConnection = nil
            return .connect(from: id, point: point, target: nil)
        }
        guard id != root.id else { return .pan(last: .zero) }
        selection = id
        return .node(id: id, offset: .zero, target: nil)
    }

    /// Mitte der geraden Linie zwischen den Knoten einer Verbindung.
    private static func straightMid(_ renderer: MapRenderer, _ connection: Connection) -> CGPoint {
        guard let a = renderer.layout.nodes[connection.from]?.frame,
              let b = renderer.layout.nodes[connection.to]?.frame else { return .zero }
        return CGPoint(x: (a.midX + b.midX) / 2, y: (a.midY + b.midY) / 2)
    }

    // MARK: - Kontextmenü, Bilder ablegen (M7)

    private func contextMenu(at location: CGPoint) -> NSMenu? {
        guard editingNode == nil else { return nil }
        let point = canvas.viewport.toMap(location)
        isFocused.wrappedValue = true
        if hitNode(point) == nil, let connection = renderer.connection(at: point) {
            selectedConnection = connection
            selection = nil
            return NSMenu.build(interaction.connectionMenu(connection))
        }
        guard let id = hitNode(point) else {
            let entries = interaction.canvasMenu()
            return entries.isEmpty ? nil : NSMenu.build(entries)
        }
        selectedConnection = nil
        selection = id
        return NSMenu.build(interaction.nodeMenu(id))
    }

    /// Ablegen auf der Map: Dateien und Bilder wie bisher, sonst Links auf den Knoten darunter (1.3).
    private func handleDrop(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return dropImage(providers, at: location)
        }
        return dropLink(provider, at: location)
    }

    /// Link (z. B. eine PDF-Stelle aus MintMarkPDF) auf einen Knoten ziehen: setzt dessen Link (Rückgängig wie
    /// „Link setzen“). Nur erlaubte Schemata, nie ein Anlegen-Link; ohne Knoten unter dem Mauszeiger passiert nichts.
    private func dropLink(_ provider: NSItemProvider, at location: CGPoint) -> Bool {
        guard let target = hitNode(canvas.viewport.toMap(location)) else { return false }
        let setLink: (String?) -> Void = { text in
            guard let text, let link = ExternalNodeRequest.acceptedLink(text) else { return }
            DispatchQueue.main.async {
                actions.setLink(link, of: target)
                selection = target
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in setLink(url?.absoluteString) }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            _ = provider.loadObject(ofClass: String.self) { text, _ in setLink(text) }
        } else {
            return false
        }
        return true
    }

    private func dropImage(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        guard let provider = providers.first else { return false }
        let target = hitNode(canvas.viewport.toMap(location)) ?? selection ?? root.id
        ImageImport.loadData(from: provider) { data in
            guard let data else { return }
            DispatchQueue.main.async {
                if actions.insertImage(data, into: target) { selection = target }
            }
        }
        return true
    }

    // MARK: - Tastatur

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard editingNode == nil,
              press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        switch press.key {
        case .tab:
            addChild(to: selection ?? root.id)
        case .return:
            addSibling()
        case .space:
            guard let id = selection else { return .ignored }
            editingNode = id
        case .upArrow:
            moveSelection(.up)
        case .downArrow:
            moveSelection(.down)
        case .leftArrow:
            moveSelection(.left)
        case .rightArrow:
            moveSelection(.right)
        default:
            return .ignored
        }
        return .handled
    }

    private func copyCommand() -> [NSItemProvider] {
        guard editingNode == nil, let id = selection, let node = root.node(withID: id) else { return [] }
        interaction.copyStyle(id)
        return [NSItemProvider(object: node.text as NSString)]
    }

    private func deleteSelection() {
        guard editingNode == nil, let id = selection, id != root.id else { return }
        selection = actions.delete(id)
    }

    private func addChild(to parentID: UUID) {
        let id = actions.addChild(to: parentID)
        selection = id
        editingNode = id
    }

    private func addSibling() {
        let id = actions.addSibling(after: selection ?? root.id)
        selection = id
        editingNode = id
    }

    private func moveSelection(_ direction: MoveDirection) {
        if let target = MapNavigation.target(from: selection, direction: direction,
                                             layout: layout, rootID: root.id) {
            selection = target
        }
    }

    private func reveal(_ id: UUID?) {
        guard let id, let frame = layout.nodes[id]?.frame else { return }
        canvas.reveal(frame)
    }
}

/// Textfeld über einem Knoten. ↩ oder Klick daneben übernimmt den Text, Esc bricht ab.
struct InlineNodeEditor: View {
    let text: String
    let font: Font
    let textColor: Color
    /// Wird bei jedem Tastendruck aufgerufen, damit die Outline sofort mitläuft.
    let onLiveChange: (String) -> Void
    let onFinish: (String) -> Void
    let onCancel: () -> Void

    @State private var draft = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .accessibilityLabel(L("Knotentext"))
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(textColor)
            .multilineTextAlignment(.center)
            .focused($focused)
            .onAppear {
                draft = text
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: draft) { _, newDraft in
                if !finished { onLiveChange(newDraft) }
            }
            .onSubmit { finish() }
            .onExitCommand {
                finished = true
                onCancel()
            }
            .onChange(of: focused) { wasFocused, isFocused in
                if wasFocused && !isFocused { finish() }
            }
            .onDisappear { finish() }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish(draft)
    }
}
