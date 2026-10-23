import SwiftUI
import AppKit

/// Welche Ansichten das Fenster zeigt.
enum EditorLayout: String, CaseIterable, Identifiable {
    case both, map, outline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .both: return L("Mindmap und Outline")
        case .map: return L("Nur Mindmap")
        case .outline: return L("Nur Outline")
        }
    }

    var symbol: String {
        switch self {
        case .both: return "rectangle.split.2x1"
        case .map: return "point.3.connected.trianglepath.dotted"
        case .outline: return "list.bullet.indent"
        }
    }

    /// Reihenfolge für ⌘ O (Ansicht wechseln).
    var next: EditorLayout {
        switch self {
        case .both: return .map
        case .map: return .outline
        case .outline: return .both
        }
    }
}

/// Hervorheben: nur passende Knoten kräftig zeigen, den Rest blass (M6).
enum HighlightMode: Equatable {
    case none
    case openTasks
    case tag(String)

    var title: String {
        switch self {
        case .none: return "nichts"
        case .openTasks: return L("offene Aufgaben")
        case .tag(let tag): return L("Tag „%@“", tag)
        }
    }
}

/// Was die Menüs im aktiven Dokumentfenster auslösen können.
struct EditorMenuActions {
    struct TagItem {
        let name: String
        let isOn: Bool
        let count: Int
    }

    var layout: EditorLayout
    var setLayout: (EditorLayout) -> Void
    var canToggleCollapse: Bool
    var toggleCollapse: () -> Void
    var export: () -> Void
    // M6
    var hasSelection: Bool
    var toggleTask: () -> Void
    var toggleDone: () -> Void
    var tags: [TagItem]
    var toggleTag: (String) -> Void
    var highlight: HighlightMode
    var setHighlight: (HighlightMode) -> Void
    var inspectorShown: Bool
    var toggleInspector: () -> Void
    var editNote: () -> Void
    var find: () -> Void
    var findNext: () -> Void
    var findPrevious: () -> Void
    // M7
    var focusMode: Bool
    var toggleFocus: () -> Void
    var present: () -> Void
    var editLink: () -> Void
    var insertImage: () -> Void
    var editFormula: () -> Void
    var startConnection: () -> Void
    // M8
    var canPasteStyle: Bool
    var hasNodeStyle: Bool
    var copyStyle: () -> Void
    var pasteStyle: () -> Void
    var resetStyle: () -> Void
    /// Eigene Form des ausgewählten Knotens (`nil` = wie im Thema).
    var shape: Theme.NodeShape?
    var setShape: (Theme.NodeShape?) -> Void
    var mapLayout: MapStyle.Layout
    var setMapLayout: (MapStyle.Layout) -> Void
    var hasMovedNodes: Bool
    var resetPositions: () -> Void
    var showInspectorTab: (InspectorTab) -> Void
    var print: () -> Void
    // M9
    var remindersSync: Bool
    var toggleRemindersSync: () -> Void
    // M10
    var showHistory: () -> Void
    // ⌘ B / ⌘ K: ganzen Knoten fett bzw. kursiv
    var toggleBold: () -> Void
    var toggleItalic: () -> Void
    // 1.1.2: Knoten anlegen/löschen (vorher nur über die Werkzeugleiste)
    var addChild: () -> Void
    var addSibling: () -> Void
    var canDelete: Bool
    var deleteNode: () -> Void
}

/// Knoten, der nach dem Öffnen eines Dokuments ausgewählt werden soll (Aufgaben in der Bibliothek).
enum PendingSelection {
    static let notification = Notification.Name("MindMapsSelectNode")
    private static var pending: [String: UUID] = [:]

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    static func set(_ id: UUID, for url: URL) {
        pending[key(url)] = id
        // Ist das Dokument schon offen, reagiert sein Fenster auf die Nachricht.
        NotificationCenter.default.post(name: notification, object: url)
    }

    static func take(for url: URL) -> UUID? {
        pending.removeValue(forKey: key(url))
    }
}

struct CanvasModelKey: FocusedValueKey {
    typealias Value = CanvasModel
}

struct EditorMenuActionsKey: FocusedValueKey {
    typealias Value = EditorMenuActions
}

extension FocusedValues {
    var canvasModel: CanvasModel? {
        get { self[CanvasModelKey.self] }
        set { self[CanvasModelKey.self] = newValue }
    }

    var editorMenu: EditorMenuActions? {
        get { self[EditorMenuActionsKey.self] }
        set { self[EditorMenuActionsKey.self] = newValue }
    }
}

/// Menüeinträge für das aktive Dokumentfenster: Ansicht, Zoom (Menü „Darstellung“) und Knoten.
struct AppCommands: Commands {
    @FocusedValue(\.canvasModel) private var canvas
    @FocusedValue(\.editorMenu) private var editor
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Dokumentverlauf (M10): Ablage › Verlauf …
        CommandGroup(after: .saveItem) {
            Button("Verlauf …") { editor?.showHistory() }
                .disabled(editor == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Drucken …") { editor?.print() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(editor == nil)
        }

        CommandGroup(replacing: .importExport) {
            Button("Importieren …") {
                ImportController.chooseAndImport(into: ImportController.libraryRoot)
            }
            .keyboardShortcut("i", modifiers: .command)
            Button("Exportieren …") { editor?.export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(editor == nil)
        }

        CommandGroup(before: .textEditing) {
            Button("Suchen & Ersetzen …") { editor?.find() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(editor == nil)
            Button("Weitersuchen") { editor?.findNext() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(editor == nil)
            Button("Rückwärts suchen") { editor?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(editor == nil)
            Divider()
        }

        CommandGroup(before: .windowList) {
            Button("Bibliothek") { openWindow(id: LibraryView.windowID) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
        }

        CommandGroup(after: .toolbar) {
            ForEach(EditorLayout.allCases) { layout in
                Button(editor?.layout == layout ? "✓ " + layout.title : layout.title) {
                    editor?.setLayout(layout)
                }
                .disabled(editor == nil)
            }
            Button("Ansicht wechseln") {
                if let editor { editor.setLayout(editor.layout.next) }
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(editor == nil)
            Divider()

            Button("Vergrößern") { canvas?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(canvas == nil)
            Button("Verkleinern") { canvas?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(canvas == nil)
            Button("An Fenster anpassen") { canvas?.zoomToFit() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(canvas == nil)
            Button("Originalgröße") { canvas?.actualSize() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(canvas == nil)
            Divider()

            Button(editor?.inspectorShown == true ? L("Seitenleiste ausblenden") : L("Seitenleiste einblenden")) {
                editor?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(editor == nil)
            Menu("Hervorheben") {
                Toggle("Nichts", isOn: highlightBinding(.none))
                Toggle("Offene Aufgaben", isOn: highlightBinding(.openTasks))
                Divider()
                ForEach(editor?.tags ?? [], id: \.name) { tag in
                    Toggle(tag.count > 0 ? "\(tag.name) (\(tag.count))" : tag.name,
                           isOn: highlightBinding(.tag(tag.name)))
                }
            }
            .disabled(editor == nil)
            Divider()

            Button(editor?.focusMode == true ? L("Fokus beenden") : L("Fokus auf ausgewählten Zweig")) { editor?.toggleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .option])
                .disabled(editor == nil)
            Button("Präsentation starten") { editor?.present() }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(editor == nil)
            Divider()
        }

        CommandMenu("Knoten") {
            Button("Unterknoten hinzufügen") { editor?.addChild() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(editor == nil)
            Button("Knoten danach") { editor?.addSibling() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!(editor?.hasSelection ?? false))
            Button("Knoten löschen") { editor?.deleteNode() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(editor?.canDelete ?? false))
            Divider()
            Button("Einklappen / Aufklappen") { editor?.toggleCollapse() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!(editor?.canToggleCollapse ?? false))
            Divider()
            Button("Als Aufgabe markieren / entfernen") { editor?.toggleTask() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!(editor?.hasSelection ?? false))
            Button("Abhaken / wieder öffnen") { editor?.toggleDone() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!(editor?.hasSelection ?? false))
            Toggle("Aufgaben mit Erinnerungen abgleichen", isOn: Binding(
                get: { editor?.remindersSync ?? false },
                set: { _ in editor?.toggleRemindersSync() }))
                .disabled(editor == nil)
            Divider()
            Button("Notiz bearbeiten") { editor?.editNote() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!(editor?.hasSelection ?? false))
            Menu("Tags") {
                let tags = editor?.tags ?? []
                ForEach(Array(tags.enumerated()), id: \.element.name) { index, tag in
                    tagToggle(tag, index: index)
                }
            }
            .disabled(!(editor?.hasSelection ?? false))
            Divider()
            // Im Notizfeld: Link für den markierten Text, sonst Link des Knotens.
            Button("Link …") { if !NoteFormatting.link() { editor?.editLink() } }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!(editor?.hasSelection ?? false))
            Button("Bild einfügen …") { editor?.insertImage() }
                .disabled(!(editor?.hasSelection ?? false))
            Button("Formel …") { editor?.editFormula() }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(!(editor?.hasSelection ?? false))
            Button("Verbindung zu …") { editor?.startConnection() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!(editor?.hasSelection ?? false))
        }

        CommandMenu("Format") {
            // Im Notizfeld: markierter Text. Sonst: der ganze ausgewählte Knoten.
            Button("Fett") { if !NoteFormatting.bold() { editor?.toggleBold() } }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(editor == nil)
            Button("Kursiv") { if !NoteFormatting.italic() { editor?.toggleItalic() } }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(editor == nil)
            Divider()
            // In der Map kopiert auch ⌘ C den Stil (siehe MapSurface.onCopyCommand).
            Button("Stil kopieren") { editor?.copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(!(editor?.hasSelection ?? false))
            Button("Stil einsetzen") { editor?.pasteStyle() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!(editor?.canPasteStyle ?? false))
            Button("Stil zurücksetzen") { editor?.resetStyle() }
                .disabled(!(editor?.hasNodeStyle ?? false))
            Divider()
            Menu("Form") {
                Toggle("Wie im Thema", isOn: shapeBinding(nil))
                Divider()
                ForEach(Theme.NodeShape.allCases, id: \.self) { shape in
                    Toggle(shape.title, isOn: shapeBinding(shape))
                }
            }
            .disabled(!(editor?.hasSelection ?? false))
            Menu("Layout") {
                ForEach(MapStyle.Layout.allCases) { layout in
                    Toggle(layout.title, isOn: Binding(get: { editor?.mapLayout == layout },
                                                       set: { _ in editor?.setMapLayout(layout) }))
                }
            }
            .disabled(editor == nil)
            Button("Alle Positionen zurücksetzen") { editor?.resetPositions() }
                .disabled(!(editor?.hasMovedNodes ?? false))
            Divider()
            Button("Stil …") { editor?.showInspectorTab(.style) }
                .disabled(editor == nil)
            Button("Layout …") { editor?.showInspectorTab(.layout) }
                .disabled(editor == nil)
            Button("Thema …") { editor?.showInspectorTab(.theme) }
                .disabled(editor == nil)
        }
    }

    private func shapeBinding(_ shape: Theme.NodeShape?) -> Binding<Bool> {
        Binding(get: { editor?.hasSelection == true && editor?.shape == shape },
                set: { _ in editor?.setShape(shape) })
    }

    /// Tag an/aus; die ersten sieben mit ⌥ ⌘ 1 … 7.
    @ViewBuilder
    private func tagToggle(_ tag: EditorMenuActions.TagItem, index: Int) -> some View {
        let toggle = Toggle(tag.name, isOn: Binding(get: { tag.isOn }, set: { _ in editor?.toggleTag(tag.name) }))
        if index < 7 {
            toggle.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
        } else {
            toggle
        }
    }

    private func highlightBinding(_ mode: HighlightMode) -> Binding<Bool> {
        Binding(get: { editor?.highlight == mode }, set: { _ in editor?.setHighlight(mode) })
    }
}
