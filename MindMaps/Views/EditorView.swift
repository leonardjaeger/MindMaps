import SwiftUI
import AppKit

/// Hauptfenster eines Dokuments: Outline und/oder Mindmap (⌘ O schaltet um).
struct EditorView: View {
    @ObservedObject var document: MindMapFile
    /// Speicherort (nil bei neuen, noch nicht gesicherten Dokumenten) – für den Export-Dateinamen.
    var fileURL: URL?
    @Environment(\.undoManager) private var undoManager

    /// Zoom und Verschiebung. Absichtlich `@State` statt `@StateObject`: Das Fenster soll beim
    /// Zoomen nicht neu gezeichnet werden, nur die Arbeitsfläche (die beobachtet das Modell selbst).
    @State private var canvas = CanvasModel()
    /// Gewählte Ansicht, wird pro Fenster gemerkt. Neue Fenster zeigen nur die Map (1.1.2).
    @SceneStorage("editorLayout") private var layoutMode: EditorLayout = .map
    @State private var selection: UUID?
    /// Knoten, der gerade in der Map bearbeitet wird.
    @State private var editingNode: UUID?
    /// Text, der gerade getippt, aber noch nicht übernommen ist – Map und Outline zeigen ihn sofort.
    @State private var liveEdit: LiveEdit?
    /// Zeile der Outline, die den Cursor bekommen soll.
    @State private var outlineFocusRequest: UUID?
    /// Wird gerade in der Outline getippt?
    @State private var outlineActive = false
    @FocusState private var canvasFocused: Bool
    @State private var showExport = false
    /// Seitenleiste (⇧ ⌘ I), pro Fenster gemerkt.
    @SceneStorage("showInspector") private var showInspector = false
    /// Offenes Popover eines Knoten-Werkzeugs oben in der Leiste (1.1.2).
    @State private var nodeTool: NodeTool?
    /// Hervorheben: nur Knoten mit einem Tag bzw. offene Aufgaben kräftig zeigen.
    @State private var highlight: HighlightMode = .none
    @State private var find = FindState()
    @AppStorage(TagStore.key) private var tagJSON = ""
    // M7
    @State private var selectedConnection: UUID?
    /// Verbinden-Modus: Der nächste Klick auf einen Knoten legt die Verbindung an.
    @State private var connectFrom: UUID?
    /// Fokusmodus: nur der ausgewählte Zweig kräftig (⌥ ⌘ F).
    @State private var focusMode = false
    @State private var presenting = false
    @State private var enteredFullScreen = false
    @State private var imageStore = ImageStore()
    // M8
    /// Bereich, zu dem die Seitenleiste scrollen soll (Format › Stil …, Layout …).
    @State private var inspectorScroll: (target: InspectorTab, token: Int)?
    @State private var showPrint = false
    /// Ablage › Verlauf … (M10)
    @State private var showHistory = false
    /// Kopierter Stil (Format › Stil kopieren).
    @State private var clipboardStyle: NodeStyle? = StyleClipboard.style
    @Environment(\.colorScheme) private var colorScheme
    // M9
    /// Abgleich der Aufgaben mit Erinnerungen, solange das Fenster offen ist.
    @StateObject private var reminderSync = RemindersSyncController()
    // M12
    /// Einstellungen › Bedienung › Textgröße (gilt für die Seitenleiste).
    @AppStorage(InterfaceTextSize.key) private var textSize: InterfaceTextSize = .standard

    /// Hält den Bild-Zwischenspeicher eines Fensters.
    final class ImageStore {
        private var images: AssetImages?
        func images(for document: MindMapFile) -> AssetImages {
            if let images { return images }
            let created = AssetImages(lookup: { [weak document] name in document?.assets[name] })
            images = created
            return created
        }
    }

    private struct LiveEdit: Equatable {
        let id: UUID
        let text: String
    }

    private var actions: DocumentActions {
        DocumentActions(document: document, undoManager: undoManager)
    }

    private var theme: Theme { ThemeStore.theme(for: document.data) }
    private var palette: ThemePalette { theme.palette(dark: colorScheme == .dark) }

    /// Das Dokument inklusive des gerade getippten Texts.
    private var displayRoot: Node {
        var root = document.data.root
        if let live = liveEdit {
            root.updateNode(id: live.id) { node in node.text = live.text }
        }
        return root
    }

    private var tagCatalog: TagCatalog { TagStore.decode(tagJSON) }

    /// Suchtreffer im aktuellen Dokument.
    private var findMatches: [FindMatch] {
        guard find.isVisible else { return [] }
        return document.data.root.findMatches(find.query, options: find.options)
    }

    /// Blasse Knoten im Hervorheben- und Fokusmodus. Der Hauptknoten bleibt zur Orientierung sichtbar.
    private func dimmedIDs(in root: Node) -> Set<UUID> {
        var dimmed = highlightDimmed(in: root)
        if focusMode, let id = selection {
            dimmed.formUnion(root.idsOutsideFocus(of: id))
        }
        return dimmed
    }

    private func highlightDimmed(in root: Node) -> Set<UUID> {
        switch highlight {
        case .none:
            return []
        case .tag(let tag):
            return root.ids { $0.id != root.id && !$0.tags.contains(tag) }
        case .openTasks:
            return root.ids { node in
                node.id != root.id && !(node.task != nil && node.taskStatus != .done)
            }
        }
    }

    var body: some View {
        let root = displayRoot
        let matches = findMatches
        let current = matches.isEmpty ? nil : matches[min(find.index, matches.count - 1)].id
        let marks = MapMarks(dimmed: dimmedIDs(in: root), matches: Set(matches.map(\.id)), currentMatch: current)
        // Eigene Seitenleiste statt `.inspector`: Die geteilte Ansicht (HSplitView) in der
        // Inspektor-Spalte brachte AppKit in eine Layout-Endlosschleife (Absturz beim Einblenden).
        HStack(spacing: 0) {
            editorContent(root, marks: marks, matches: matches)
            if showInspector {
                Divider()
                inspectorPanel
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay {
            if presenting {
                PresentationView(data: document.data, images: imageStore.images(for: document),
                                 onClose: endPresentation)
            }
        }
        .toolbar { toolbarContent }
        .toolbar(presenting ? .hidden : .automatic, for: .windowToolbar)
        .sheet(isPresented: $showExport) {
            ExportSheet(data: document.data, assets: document.assets, baseName: exportName)
        }
        .sheet(isPresented: $showPrint) {
            PrintSheet(data: document.data, assets: document.assets, title: exportName)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(document: document, undoManager: undoManager) { restoredID in
                if let restoredID { selection = restoredID }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: StyleClipboard.notification)) { _ in
            clipboardStyle = StyleClipboard.style
        }
        .focusedSceneValue(\.canvasModel, canvas)
        .focusedSceneValue(\.editorMenu, menuActions)
        .onChange(of: document.data.root) { _, newRoot in
            validateSelection(in: newRoot)
            reminderSync.documentChanged()
        }
        .modifier(SystemLink(document: document, fileURL: fileURL, undoManager: undoManager,
                             reminderSync: reminderSync))
        .onChange(of: layoutMode) { _, mode in
            if mode != .outline {
                DispatchQueue.main.async { canvasFocused = true }
            }
        }
        .onChange(of: find.query) { _, _ in find.index = 0 }
        .onReceive(NotificationCenter.default.publisher(for: PendingSelection.notification)) { note in
            // Pfade vergleichen: Paket-URLs kommen mal mit, mal ohne „/“ am Ende (1.3).
            guard let url = note.object as? URL, let fileURL,
                  url.standardizedFileURL.path == fileURL.standardizedFileURL.path,
                  let id = PendingSelection.take(for: fileURL) else { return }
            show(id)
        }
        .onAppear {
            if selection == nil { selection = document.data.root.id }
            if let fileURL, let id = PendingSelection.take(for: fileURL) {
                DispatchQueue.main.async { show(id) }
            }
            if layoutMode != .outline {
                DispatchQueue.main.async { canvasFocused = true }
            }
        }
    }

    /// Outline und/oder Map mit Suchleiste und Hinweis zum Hervorheben.
    private func editorContent(_ root: Node, marks: MapMarks, matches: [FindMatch]) -> some View {
        Group {
            switch layoutMode {
            case .both:
                HSplitView {
                    outlineView(root, marks: marks)
                        .frame(minWidth: 200, idealWidth: 280, maxWidth: 420)
                    mapView(root, marks: marks)
                        .frame(minWidth: 280)
                }
            case .map:
                mapView(root, marks: marks)
            case .outline:
                outlineView(root, marks: marks)
            }
        }
        .frame(minWidth: 420)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if find.isVisible {
                    FindBar(state: $find, matches: matches,
                            onNext: { stepMatch(1) }, onPrevious: { stepMatch(-1) },
                            onReplace: replaceCurrent, onReplaceAll: replaceAll,
                            onClose: closeFind)
                }
                if highlight != .none {
                    highlightBanner(root)
                }
                if connectFrom != nil {
                    infoBanner(L("Klicke auf den Knoten, zu dem die Verbindung führen soll."), symbol: "arrow.triangle.branch") {
                        connectFrom = nil
                    }
                }
                if focusMode {
                    infoBanner(L("Fokus: Nur der ausgewählte Zweig ist hervorgehoben."), symbol: "scope") {
                        focusMode = false
                    }
                }
                if case .failed(let message) = reminderSync.status, document.data.reminders != nil {
                    remindersBanner(message)
                }
                // Knoten aus MintMarkPDF angelegt (1.3) – mit Rückgängig.
                ExternalNodeBanner(fileURL: fileURL, document: document, undoManager: undoManager)
            }
        }
    }

    // MARK: - Ansichten

    private func outlineView(_ root: Node, marks: MapMarks) -> some View {
        OutlineEditorView(root: root,
                          selection: $selection,
                          focusRequest: $outlineFocusRequest,
                          handlers: outlineHandlers,
                          marks: marks,
                          tagCatalog: tagCatalog)
    }

    private func mapView(_ root: Node, marks: MapMarks) -> some View {
        MapCanvasView(root: root,
                      theme: theme,
                      selection: $selection,
                      editingNode: $editingNode,
                      canvas: canvas,
                      isFocused: $canvasFocused,
                      actions: actions,
                      onLiveText: { id, text in updateLive(id, text) },
                      marks: marks,
                      interaction: MapInteraction(
                        images: imageStore.images(for: document),
                        connections: document.data.connections,
                        selectedConnection: $selectedConnection,
                        connectFrom: $connectFrom,
                        nodeMenu: nodeMenu,
                        connectionMenu: connectionMenu,
                        openLink: openLink,
                        editConnectionLabel: editConnectionLabel,
                        canvasMenu: canvasMenu,
                        copyStyle: { id in copyStyle(of: id) }),
                      mapStyle: document.data.style)
            .overlay(alignment: .bottom) {
                // Tipp für neue, leere Maps (1.1.2) – verschwindet mit dem ersten Unterknoten.
                if root.children.isEmpty && !presenting {
                    StartTip()
                        .padding(.bottom, 18)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: root.children.isEmpty)
    }

    private func infoBanner(_ text: String, symbol: String, onEnd: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text).font(.callout)
            Spacer()
            Button("Beenden", action: onEnd)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Hinweis, wenn der Abgleich mit Erinnerungen nicht klappt (M9).
    private func remindersBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Erneut versuchen") {
                Task { await reminderSync.retry(actions: actions) }
            }
            Button("Abgleich beenden") { reminderSync.disable(actions: actions) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    /// Knoten › Aufgaben mit Erinnerungen abgleichen (M9).
    private func toggleRemindersSync() {
        if document.data.reminders != nil {
            reminderSync.disable(actions: actions)
        } else {
            Task {
                if let problem = await reminderSync.enable(actions: actions) {
                    let alert = NSAlert()
                    alert.messageText = L("Abgleich mit Erinnerungen nicht möglich")
                    alert.informativeText = problem
                    alert.runModal()
                }
            }
        }
    }

    private func highlightBanner(_ root: Node) -> some View {
        let count: Int
        switch highlight {
        case .none: count = 0
        case .tag(let tag): count = root.tagCounts[tag] ?? 0
        case .openTasks: count = root.openTasks().count
        }
        return HStack(spacing: 8) {
            Image(systemName: "highlighter")
            Text(L("Hervorgehoben: %@ (%@)", highlight.title, "\(count)"))
                .font(.callout)
            Spacer()
            Button("Beenden") { highlight = .none }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Ansicht", selection: $layoutMode) {
                ForEach(EditorLayout.allCases) { layout in
                    Image(systemName: layout.symbol)
                        .accessibilityLabel(layout.title)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("Mindmap und Outline / nur Mindmap / nur Outline (⌘ O)")
        }

        // Knoten-Werkzeuge (1.1.2): erscheinen, sobald ein Knoten ausgewählt ist – je ein Popover
        // für Aufgabe, Tags, Notiz, Link/Bild/Formel und Stil.
        if let node = selection.flatMap({ document.data.root.node(withID: $0) }) {
            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(NodeTool.allCases) { tool in
                    nodeToolButton(tool, node: node)
                }
            }
        }

        // Schlanke Werkzeugleiste (1.1.2): Unterknoten, Präsentieren, Teilen, Seitenleiste.
        // Löschen, Einpassen und „Knoten danach“ gibt es über Menüs und Tasten.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                addNode(asChild: true)
            } label: {
                Label("Unterknoten", systemImage: "plus")
            }
            .help("Unterknoten zum ausgewählten Knoten – beim Hauptknoten ein neuer Hauptzweig (Tab bzw. ⌘ ↩)")

            Button {
                startPresentation()
            } label: {
                Label("Präsentieren", systemImage: "play")
            }
            .help("Präsentation: Zweig für Zweig im Vollbild (⌥ ⌘ P)")

            Button {
                showExport = true
            } label: {
                Label("Teilen", systemImage: "square.and.arrow.up")
            }
            .help("Als Markdown, OPML, PDF, PNG, SVG … exportieren oder senden (⇧ ⌘ E)")

            Button {
                showInspector.toggle()
            } label: {
                Label("Seitenleiste", systemImage: "sidebar.right")
            }
            .help("Seitenleiste: Themen und Layout der Mindmap (⇧ ⌘ I)")
        }
    }

    /// Knopf eines Knoten-Werkzeugs mit Popover (1.1.2).
    private func nodeToolButton(_ tool: NodeTool, node: Node) -> some View {
        Button {
            nodeTool = nodeTool == tool ? nil : tool
        } label: {
            Label(tool.title, systemImage: symbol(for: tool, node: node))
        }
        .help(tool.title)
        .popover(isPresented: Binding(get: { nodeTool == tool },
                                      set: { open in if !open, nodeTool == tool { nodeTool = nil } }),
                 arrowEdge: .bottom) {
            nodeToolContent(tool, node: node)
        }
    }

    /// Ausgefülltes Symbol, wenn der Knoten schon etwas davon hat (Aufgabe, Tags, Notiz, Anhang, eigener Stil).
    private func symbol(for tool: NodeTool, node: Node) -> String {
        let used: Bool
        switch tool {
        case .task: used = node.task != nil
        case .tags: used = !node.tags.isEmpty
        case .note: used = !node.note.isEmpty
        case .media: used = !node.link.isEmpty || node.image != nil || !node.formula.isEmpty
        case .style: used = node.style != nil
        }
        guard used else { return tool.symbol }
        switch tool {
        case .task: return "checkmark.square.fill"
        case .tags: return "tag.fill"
        case .media: return "paperclip.circle.fill"
        case .style: return "paintbrush.fill"
        case .note: return tool.symbol
        }
    }

    @ViewBuilder
    private func nodeToolContent(_ tool: NodeTool, node: Node) -> some View {
        let isRoot = node.id == document.data.root.id
        switch tool {
        case .note:
            NotePopover(node: node, actions: actions)
        case .style:
            ScrollView {
                styleInspector.padding(14)
            }
            .frame(width: 320, height: 520)
        case .task, .tags, .media:
            NodeInspector(node: node,
                          part: tool == .task ? .task : (tool == .tags ? .tags : .media),
                          isRoot: isRoot,
                          actions: actions,
                          noteFocusToken: 0,
                          noteFocusNode: nil,
                          images: imageStore.images(for: document),
                          fileURL: fileURL,
                          openLink: openLink)
                .padding(14)
                .frame(width: 320)
        }
    }

    /// Dateiname für den Export: Name der Datei, sonst Text des Hauptknotens.
    private var exportName: String {
        if let fileURL { return fileURL.deletingPathExtension().lastPathComponent }
        let text = document.data.root.text
            .components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? L("Mindmap") : String(text.prefix(80))
    }

    // MARK: - Menüs

    private var menuActions: EditorMenuActions {
        let root = document.data.root
        let counts = root.tagCounts
        let selectedTags = selection.flatMap { root.node(withID: $0) }?.tags ?? []
        return EditorMenuActions(
            layout: layoutMode,
            setLayout: { layout in layoutMode = layout },
            canToggleCollapse: selection.map { root.canToggleCollapse($0) } ?? false,
            toggleCollapse: {
                if let id = selection { actions.toggleCollapsed(id) }
            },
            export: { showExport = true },
            hasSelection: selection != nil,
            toggleTask: { if let id = selection { actions.toggleTask(id) } },
            toggleDone: { if let id = selection { actions.toggleDone(id) } },
            tags: tagCatalog.ordered(including: counts.keys).map { tag in
                EditorMenuActions.TagItem(name: tag, isOn: selectedTags.contains(tag), count: counts[tag] ?? 0)
            },
            toggleTag: { tag in if let id = selection { actions.toggleTag(tag, on: id) } },
            highlight: highlight,
            setHighlight: { mode in highlight = mode },
            inspectorShown: showInspector,
            toggleInspector: { showInspector.toggle() },
            editNote: { editNote(selection) },
            find: openFind,
            findNext: { stepMatch(1) },
            findPrevious: { stepMatch(-1) },
            focusMode: focusMode,
            toggleFocus: { focusMode.toggle() },
            present: startPresentation,
            editLink: { if let id = selection { editLink(id) } },
            insertImage: { if let id = selection { chooseImage(for: id) } },
            editFormula: { if let id = selection { editFormula(id) } },
            startConnection: { if let id = selection { connectFrom = id } },
            canPasteStyle: clipboardStyle != nil && selection != nil,
            hasNodeStyle: selection.flatMap { root.node(withID: $0) }?.style != nil,
            copyStyle: { if let id = selection { copyStyle(of: id) } },
            pasteStyle: { if let id = selection { pasteStyle(on: id) } },
            resetStyle: { if let id = selection { actions.setNodeStyle(nil, of: id, actionName: "Stil zurücksetzen") } },
            shape: selection.flatMap { root.node(withID: $0) }?.style?.shape,
            setShape: { shape in if let id = selection { actions.setShape(shape, of: id) } },
            mapLayout: document.data.style.layout,
            setMapLayout: { layout in actions.setLayout(layout) },
            hasMovedNodes: root.movedNodeCount > 0,
            resetPositions: { actions.resetAllPositions() },
            showInspectorTab: { tab in showInspectorTab(tab) },
            print: { showPrint = true },
            remindersSync: document.data.reminders != nil,
            toggleRemindersSync: toggleRemindersSync,
            showHistory: { showHistory = true },
            toggleBold: { if let id = selection { toggleBold(id) } },
            toggleItalic: { if let id = selection { toggleItalic(id) } },
            addChild: { addNode(asChild: true) },
            addSibling: { addNode(asChild: false) },
            canDelete: selection != nil && selection != root.id,
            deleteNode: deleteSelection)
    }

    // MARK: - Outline

    private var outlineHandlers: OutlineHandlers {
        OutlineHandlers(
            focused: { id in
                outlineActive = true
                selection = id
            },
            endEditing: { id, text in
                actions.setText(text, of: id)
                updateLive(id, nil)
                outlineActive = false
            },
            liveText: { id, text in updateLive(id, text) },
            command: handleOutlineCommand,
            toggleCollapsed: { id in actions.toggleCollapsed(id) },
            move: { id, target, position in
                switch position {
                case .before: actions.move(id, beside: target, after: false)
                case .after: actions.move(id, beside: target, after: true)
                case .inside: actions.move(id, to: target)
                }
                selection = id
            },
            canMove: { id, target, position in
                let root = document.data.root
                return position == .inside
                    ? root.canMove(id, toParent: target)
                    : root.canMove(id, beside: target)
            },
            delete: deleteSelection,
            toggleDone: { id in actions.toggleDone(id) },
            openNote: { id in editNote(id) },
            contextMenu: { id in nodeMenu(id) })
    }

    // MARK: - Kontextmenü, Links, Bilder, Formeln, Präsentation (M7)

    /// Alle Aktionen für einen Knoten – Rechtsklick in Map und Outline.
    private func nodeMenu(_ id: UUID) -> [MenuEntry] {
        let root = document.data.root
        guard let node = root.node(withID: id) else { return [] }
        let isRoot = id == root.id
        let counts = root.tagCounts
        var entries: [MenuEntry] = [
            .action(L("Unterknoten hinzufügen"), systemImage: "arrow.turn.down.right") {
                selection = id
                addNode(asChild: true)
            },
            .action(L("Knoten danach"), systemImage: "plus.rectangle.on.rectangle", enabled: !isRoot) {
                selection = id
                addNode(asChild: false)
            },
            .divider,
            .action(L("Text bearbeiten"), systemImage: "pencil") {
                selection = id
                if layoutMode == .outline { outlineFocusRequest = id } else { editingNode = id }
            },
            .action(L("Notiz bearbeiten"), systemImage: "note.text") { editNote(id) },
            .divider,
            .action(node.task == nil ? L("Als Aufgabe markieren") : L("Aufgabe entfernen"), systemImage: "checkmark.square") {
                actions.toggleTask(id)
            },
        ]
        if node.task != nil || node.hasTaskDescendants {
            entries.append(.action(node.taskStatus == .done ? L("Wieder öffnen") : L("Abhaken"), systemImage: "checkmark") {
                actions.toggleDone(id)
            })
        }
        entries.append(.submenu(L("Tags"), systemImage: "tag", tagCatalog.ordered(including: counts.keys).map { tag in
            .toggle(tag, isOn: node.tags.contains(tag)) { actions.toggleTag(tag, on: id) }
        }))
        entries.append(.divider)
        entries.append(.action(node.link.isEmpty ? L("Link hinzufügen …") : L("Link ändern …"), systemImage: "link") {
            editLink(id)
        })
        if !node.link.isEmpty {
            entries.append(.action(L("Link öffnen"), systemImage: "arrow.up.forward.square") { openLink(node.link) })
        }
        entries.append(.action(L("Link zu diesem Knoten kopieren"), systemImage: "doc.on.doc", enabled: fileURL != nil) {
            copyNodeLink(id)
        })
        entries.append(.divider)
        entries.append(.action(node.image == nil ? L("Bild einfügen …") : L("Bild ersetzen …"), systemImage: "photo") {
            chooseImage(for: id)
        })
        if let image = node.image {
            entries.append(.submenu(L("Bildgröße"), systemImage: "arrow.up.left.and.arrow.down.right", [
                .toggle(L("Klein"), isOn: image.width == 120) { actions.resizeImage(of: id, toWidth: 120) },
                .toggle(L("Mittel"), isOn: image.width == 220) { actions.resizeImage(of: id, toWidth: 220) },
                .toggle(L("Groß"), isOn: image.width == 360) { actions.resizeImage(of: id, toWidth: 360) },
            ]))
            entries.append(.action(L("Bild entfernen"), systemImage: "photo.badge.minus") { actions.removeImage(of: id) })
        }
        entries.append(.action(node.formula.isEmpty ? L("Formel hinzufügen …") : L("Formel ändern …"), systemImage: "function") {
            editFormula(id)
        })
        if !node.formula.isEmpty {
            entries.append(.action(L("Formel entfernen"), systemImage: "minus.circle") { actions.setFormula("", of: id) })
        }
        entries.append(.divider)
        entries.append(.action(L("Verbindung zu …"), systemImage: "arrow.triangle.branch") {
            selection = id
            connectFrom = id
        })
        entries.append(.action(L("Fokus auf diesen Zweig"), systemImage: "scope") {
            selection = id
            focusMode = true
        })
        if root.canToggleCollapse(id) {
            entries.append(.action(node.isCollapsed ? L("Aufklappen") : L("Einklappen"), systemImage: "chevron.down") {
                actions.toggleCollapsed(id)
            })
        }
        entries.append(.divider)
        entries.append(.action(L("Stil …"), systemImage: "paintbrush") {
            selection = id
            showInspectorTab(.style)
        })
        var shapes: [MenuEntry] = [
            .toggle(L("Wie im Thema"), isOn: node.style?.shape == nil) { actions.setShape(nil, of: id) },
            .divider,
        ]
        for shape in Theme.NodeShape.allCases {
            shapes.append(.toggle(shape.title, isOn: node.style?.shape == shape) { actions.setShape(shape, of: id) })
        }
        entries.append(.submenu(L("Form"), systemImage: "square.on.circle", shapes))
        entries.append(.action(L("Stil kopieren"), systemImage: "eyedropper") { copyStyle(of: id) })
        entries.append(.action(L("Stil einsetzen"), systemImage: "paintbrush.pointed", enabled: clipboardStyle != nil) {
            pasteStyle(on: id)
        })
        if node.style != nil {
            entries.append(.action(L("Stil zurücksetzen"), systemImage: "arrow.uturn.backward") {
                actions.setNodeStyle(nil, of: id, actionName: "Stil zurücksetzen")
            })
        }
        if node.offset != nil {
            entries.append(.action(L("Position zurücksetzen"), systemImage: "arrow.uturn.backward.circle") {
                actions.resetPosition(of: id)
            })
        }
        if !isRoot {
            entries.append(.divider)
            entries.append(.action(L("Löschen"), systemImage: "trash") {
                selection = id
                deleteSelection()
            })
        }
        return entries
    }

    // MARK: - Gestaltung (M8)

    /// Rechtsklick auf die freie Fläche der Map.
    private func canvasMenu() -> [MenuEntry] {
        let data = document.data
        return [
            .submenu(L("Layout"), systemImage: "rectangle.3.group", MapStyle.Layout.allCases.map { layout in
                .toggle(layout.title, isOn: data.style.layout == layout) { actions.setLayout(layout) }
            }),
            .action(L("Alle Positionen zurücksetzen"), systemImage: "arrow.uturn.backward",
                    enabled: data.root.movedNodeCount > 0) { actions.resetAllPositions() },
            .divider,
            .action(L("Layout …"), systemImage: "slider.horizontal.3") { showInspectorTab(.layout) },
            .action(L("Thema …"), systemImage: "paintpalette") { showInspectorTab(.theme) },
            .divider,
            .action(L("An Fenster anpassen"), systemImage: "arrow.up.left.and.down.right.magnifyingglass") { canvas.zoomToFit() },
        ]
    }

    /// Stil/Info öffnen das Popover oben in der Leiste, Thema/Layout die Seitenleiste (1.1.2).
    private func showInspectorTab(_ tab: InspectorTab) {
        if let tool = tab.nodeTool {
            guard selection != nil else { return }
            DispatchQueue.main.async { nodeTool = tool }
            return
        }
        showInspector = true
        inspectorScroll = (tab, (inspectorScroll?.token ?? 0) + 1)
    }

    /// ⌘ B: ganzer Knoten fett / nicht fett. Entspricht das dem Thema, bleibt kein eigener Stil übrig.
    private func toggleBold(_ id: UUID) {
        let root = document.data.root
        guard let node = root.node(withID: id) else { return }
        let depth = max((root.path(to: id)?.count ?? 1) - 1, 0)
        let metrics = NodeMetrics(theme: theme, style: document.data.style)
        let isBold = metrics.weight(for: node, depth: depth) == .bold
        var plain = node
        plain.style?.bold = nil
        let themeBold = metrics.weight(for: plain, depth: depth) == .bold
        actions.updateNodeStyle(id, L("Fett")) { $0.bold = !isBold == themeBold ? nil : !isBold }
    }

    /// ⌘ K: ganzer Knoten kursiv / nicht kursiv.
    private func toggleItalic(_ id: UUID) {
        let isItalic = document.data.root.node(withID: id)?.style?.italic ?? false
        actions.updateNodeStyle(id, L("Kursiv")) { $0.italic = isItalic ? nil : true }
    }

    private func copyStyle(of id: UUID) {
        StyleClipboard.style = document.data.root.node(withID: id)?.style ?? NodeStyle()
    }

    private func pasteStyle(on id: UUID) {
        guard let style = StyleClipboard.style else { return }
        actions.setNodeStyle(style, of: id)
    }

    /// Seitenleiste (⇧ ⌘ I): Themen und Layout der Mindmap. Alles zum einzelnen Knoten steht
    /// seit 1.1.2 oben in der Werkzeugleiste.
    private var inspectorPanel: some View {
        mapPage
            .font(textSize == .standard ? nil : .system(size: textSize.pointSize))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var mapPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ThemeSection(data: document.data, actions: actions)
                        .id(InspectorTab.theme)
                    Divider()
                    LayoutSection(style: document.data.style, theme: theme,
                                  movedCount: document.data.root.movedNodeCount, actions: actions)
                        .id(InspectorTab.layout)
                }
                .padding(14)
            }
            .onChange(of: inspectorScroll?.token) { _, _ in
                guard let target = inspectorScroll?.target, target.nodeTool == nil else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private var styleInspector: some View {
        let root = document.data.root
        if let id = selection, let node = root.node(withID: id),
           let context = root.styleContext(of: id, palette: palette) {
            NodeStyleSection(node: node, depth: context.depth,
                             look: NodeAppearance.resolve(node, depth: context.depth, branchHex: context.branchHex,
                                                          theme: theme, palette: palette),
                             theme: theme, palette: palette, actions: actions,
                             canPaste: clipboardStyle != nil,
                             copyStyle: { copyStyle(of: id) },
                             pasteStyle: { pasteStyle(on: id) })
                .id(id)
        } else {
            ContentUnavailableView("Kein Knoten ausgewählt", systemImage: "paintbrush",
                                   description: Text("Wähle einen Knoten, um Form, Farben und Schrift zu ändern."))
        }
    }

    private func connectionMenu(_ id: UUID) -> [MenuEntry] {
        [
            .action(L("Beschriftung …"), systemImage: "character.cursor.ibeam") { editConnectionLabel(id) },
            .action(L("Bogen zurücksetzen"), systemImage: "arrow.uturn.backward") { actions.setConnectionBend(nil, of: id) },
            .divider,
            .action(L("Verbindung löschen"), systemImage: "trash") {
                actions.removeConnection(id)
                if selectedConnection == id { selectedConnection = nil }
            },
        ]
    }

    private func editConnectionLabel(_ id: UUID) {
        guard let connection = document.data.connections.first(where: { $0.id == id }) else { return }
        if let label = TextPrompt.run(title: L("Beschriftung der Verbindung"),
                                      message: L("Kurzer Text an der Verbindung, z. B. „führt zu“ oder „Gegenteil“."),
                                      initial: connection.label) {
            actions.setConnectionLabel(label, of: id)
        }
    }

    private func editLink(_ id: UUID) {
        guard let node = document.data.root.node(withID: id) else { return }
        if let link = TextPrompt.run(title: L("Link"),
                                     message: L("Webadresse oder Link zu einem Knoten (Kontextmenü „Link zu diesem Knoten kopieren“). Leer lassen entfernt den Link."),
                                     initial: node.link, placeholder: "https://") {
            actions.setLink(link, of: id)
        }
    }

    private func editFormula(_ id: UUID) {
        guard let node = document.data.root.node(withID: id) else { return }
        if let formula = TextPrompt.run(title: L("Formel"),
                                        message: L("LaTeX-Schreibweise, z. B. F = G \\frac{m_1 m_2}{r^2} oder a^2 + b^2 = c^2. Leer lassen entfernt die Formel."),
                                        initial: node.formula, placeholder: "E = mc^2", width: 420) {
            actions.setFormula(formula, of: id)
        }
    }

    private func chooseImage(for id: UUID) {
        guard let data = ImageImport.chooseFile() else { return }
        if !actions.insertImage(data, into: id) {
            let alert = NSAlert()
            alert.messageText = L("Das Bild ließ sich nicht lesen.")
            alert.runModal()
        }
    }

    private func copyNodeLink(_ id: UUID) {
        guard let fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DocumentLink.make(file: fileURL, node: id), forType: .string)
    }

    /// Öffnet einen Link: MindMaps-Links in der App (am richtigen Knoten), alles andere im Browser.
    private func openLink(_ link: String) {
        LinkOpener.open(link)
    }

    private func startPresentation() {
        editingNode = nil
        find.isVisible = false
        presenting = true
        if let window = NSApp.keyWindow, !window.styleMask.contains(.fullScreen) {
            enteredFullScreen = true
            window.toggleFullScreen(nil)
        }
    }

    private func endPresentation() {
        presenting = false
        if enteredFullScreen, let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        enteredFullScreen = false
        if layoutMode != .outline { DispatchQueue.main.async { canvasFocused = true } }
    }

    // MARK: - Notiz, Suchen (M6)

    /// Notiz bearbeiten: Popover „Notiz“ oben in der Leiste, Cursor gleich im Text (1.1.2).
    private func editNote(_ id: UUID?) {
        guard let id else { return }
        selection = id
        // Einen Moment später: Der Knopf erscheint erst mit der Auswahl in der Leiste.
        DispatchQueue.main.async { nodeTool = .note }
    }

    /// Wählt einen Knoten aus und klappt dafür nötige Zweige auf (Suchtreffer, Aufgabe aus der Bibliothek).
    private func show(_ id: UUID) {
        guard document.data.root.contains(id) else { return }
        actions.reveal(id)
        selection = id
    }

    private func openFind() {
        find.isVisible = true
        find.focusToken += 1
    }

    private func closeFind() {
        find.isVisible = false
        if layoutMode != .outline { canvasFocused = true }
    }

    private func stepMatch(_ step: Int) {
        if !find.isVisible { openFind() }
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let current = min(find.index, matches.count - 1)
        // Beim ersten Weitersuchen direkt zum aktuellen Treffer springen.
        let alreadyShown = selection == matches[current].id
        find.index = alreadyShown ? (current + step + matches.count) % matches.count : current
        show(matches[find.index].id)
    }

    private func replaceCurrent() {
        let matches = findMatches
        guard !matches.isEmpty else { return }
        let current = matches[min(find.index, matches.count - 1)]
        actions.replace(in: current.id, find.query, with: find.replacement, options: find.options)
        let remaining = findMatches
        guard !remaining.isEmpty else { return }
        find.index = min(find.index, remaining.count - 1)
        show(remaining[find.index].id)
    }

    private func replaceAll() {
        actions.replaceAll(find.query, with: find.replacement, options: find.options)
        find.index = 0
    }

    /// ↩, Tab, ⇧ Tab, ↑, ↓ in einer Outline-Zeile. Der getippte Text wird vorher übernommen.
    private func handleOutlineCommand(_ id: UUID, _ command: OutlineField.Command, _ draft: String) -> Bool {
        actions.setText(draft, of: id)
        updateLive(id, nil)
        switch command {
        case .newline:
            let new = actions.addSibling(after: id)
            selection = new
            outlineFocusRequest = new
        case .tab:
            actions.indent(id)
            outlineFocusRequest = id
        case .backtab:
            actions.outdent(id)
            outlineFocusRequest = id
        case .up, .down:
            let rows = document.data.root.visibleRows()
            guard let i = rows.firstIndex(where: { $0.id == id }) else { return true }
            let j = command == .up ? i - 1 : i + 1
            guard rows.indices.contains(j) else { return true }
            selection = rows[j].id
            outlineFocusRequest = rows[j].id
        }
        return true
    }

    // MARK: - Gemeinsame Aktionen

    private func updateLive(_ id: UUID, _ text: String?) {
        if let text {
            let new = LiveEdit(id: id, text: text)
            if liveEdit != new { liveEdit = new }
        } else if liveEdit?.id == id {
            liveEdit = nil
        }
    }

    private func addNode(asChild: Bool) {
        let target = selection ?? document.data.root.id
        let id = asChild ? actions.addChild(to: target) : actions.addSibling(after: target)
        selection = id
        if outlineActive || layoutMode == .outline {
            outlineFocusRequest = id
        } else {
            editingNode = id
        }
    }

    private func deleteSelection() {
        guard let id = selection, id != document.data.root.id else { return }
        selection = actions.delete(id)
    }

    /// Nach Rückgängig, Löschen oder Einklappen kann die Auswahl verschwunden oder verborgen sein.
    private func validateSelection(in root: Node) {
        if let id = selection {
            if !root.contains(id) {
                selection = root.id
            } else if let visible = root.visibleNode(for: id), visible != id {
                selection = visible
            }
        }
        if let id = editingNode, root.visibleNode(for: id) != id { editingNode = nil }
        if let live = liveEdit, !root.contains(live.id) { liveEdit = nil }
    }
}

/// Verbindet ein Dokumentfenster mit macOS (M9): meldet es für Kurzbefehle an und
/// gleicht seine Aufgaben mit Erinnerungen ab, solange es offen ist.
private struct SystemLink: ViewModifier {
    @ObservedObject var document: MindMapFile
    let fileURL: URL?
    let undoManager: UndoManager?
    let reminderSync: RemindersSyncController

    func body(content: Content) -> some View {
        content
            .onAppear { connect(fileURL) }
            .onChange(of: fileURL) { _, url in connect(url) }
            // 1.3: Kommt der Rückgängig-Verlauf erst nach dem ersten Anzeigen, neu anmelden (sonst legte ein
            // Link aus MintMarkPDF den Knoten ohne Rückgängig an).
            .onChange(of: undoManager.map(ObjectIdentifier.init)) { _, _ in connect(fileURL) }
            .onChange(of: document.data.reminders) { _, _ in reminderSync.documentChanged() }
            .onDisappear {
                OpenDocuments.unregister(document)
                reminderSync.detach()
            }
    }

    private func connect(_ url: URL?) {
        OpenDocuments.register(document, url: url, undoManager: undoManager)
        reminderSync.attach(document: document, fileURL: url, undoManager: undoManager)
    }
}

/// Kurzer Tipp unten in einer leeren Map: die wichtigsten Tasten zum Loslegen (1.1.2).
private struct StartTip: View {
    var body: some View {
        HStack(spacing: 14) {
            item("Tab", L("Unterknoten"))
            item("↩", L("Knoten danach"))
            item(L("Leertaste"), L("Text bearbeiten"))
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func item(_ key: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(text).foregroundStyle(.secondary)
        }
    }
}
