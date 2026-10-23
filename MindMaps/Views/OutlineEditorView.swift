import SwiftUI
import UniformTypeIdentifiers

/// Die Outline (Gliederung).
///
/// | Eingabe | Wirkung |
/// |---|---|
/// | Klick in den Text | bearbeiten |
/// | ↩ (beim Tippen) | neuer Knoten darunter |
/// | Tab / ⇧ Tab | eine Ebene tiefer / höher |
/// | ↑ / ↓ | vorige / nächste Zeile |
/// | Esc | Änderung verwerfen |
/// | Pfeil vor der Zeile, ⌘ . | ein-/ausklappen |
/// | Griff ≡ rechts ziehen | davor / hinein / danach ablegen |
///
/// Bewusst keine `List`: Die macOS-Liste fängt Klicks auf eigene Textfelder ab
/// (Befund aus der M3-Abnahme: Doppelklick und Schreiben ging nicht).
struct OutlineEditorView: View {
    let root: Node
    @Binding var selection: UUID?
    @Binding var focusRequest: UUID?
    let handlers: OutlineHandlers
    var marks = MapMarks()
    var tagCatalog = TagCatalog.standard

    @State private var draggedRow: UUID?
    @State private var dropIndicator: OutlineDropIndicator?
    @FocusState private var listFocused: Bool
    /// Einstellungen › Bedienung › Textgröße (M12).
    @AppStorage(InterfaceTextSize.key) private var textSize: InterfaceTextSize = .standard

    var body: some View {
        let rows = root.visibleRows()
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rows) { row in
                        OutlineRowView(row: row,
                                       isSelected: selection == row.id,
                                       isDimmed: marks.dimmed.contains(row.id),
                                       matchState: marks.currentMatch == row.id ? .current
                                           : (marks.matches.contains(row.id) ? .match : nil),
                                       tagCatalog: tagCatalog,
                                       fontSize: textSize.pointSize,
                                       focusRequest: $focusRequest,
                                       draggedRow: $draggedRow,
                                       dropIndicator: $dropIndicator,
                                       handlers: handlers,
                                       onSelect: {
                                           selection = row.id
                                           listFocused = true
                                       })
                            .id(row.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($listFocused)
            .onDeleteCommand { handlers.delete() }
            .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                handleKey(press, rows: rows)
            }
            .onChange(of: selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(root.nodeCount == 1 ? L("1 Knoten") : L("%@ Knoten", "\(root.nodeCount)"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    /// Tasten, wenn eine Zeile ausgewählt ist, aber kein Cursor im Text steht.
    private func handleKey(_ press: KeyPress, rows: [OutlineRow]) -> KeyPress.Result {
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        let index = selection.flatMap { id in rows.firstIndex { $0.id == id } }
        switch press.key {
        case .upArrow:
            let i = max((index ?? rows.count) - 1, 0)
            if rows.indices.contains(i) { selection = rows[i].id }
        case .downArrow:
            let i = min((index ?? -1) + 1, rows.count - 1)
            if rows.indices.contains(i) { selection = rows[i].id }
        case .return:
            guard let id = selection else { return .ignored }
            focusRequest = id
        default:
            return .ignored
        }
        return .handled
    }
}

/// Wo ein gezogener Knoten landen würde.
struct OutlineDropIndicator: Equatable {
    let target: UUID
    let position: OutlineDropPosition
}

/// Eine Zeile: Pfeil zum Ein-/Ausklappen, Textfeld, Griff zum Ziehen.
struct OutlineRowView: View {
    enum MatchState { case match, current }

    let row: OutlineRow
    let isSelected: Bool
    var isDimmed = false
    var matchState: MatchState?
    var tagCatalog = TagCatalog.standard
    var fontSize: CGFloat = 13
    @Binding var focusRequest: UUID?
    @Binding var draggedRow: UUID?
    @Binding var dropIndicator: OutlineDropIndicator?
    let handlers: OutlineHandlers
    let onSelect: () -> Void

    @State private var height: CGFloat = 26
    @State private var hovering = false

    private var indent: CGFloat { CGFloat(row.depth) * 16 }

    private var indicator: OutlineDropPosition? {
        guard let dropIndicator, dropIndicator.target == row.id else { return nil }
        return dropIndicator.position
    }

    var body: some View {
        HStack(spacing: 4) {
            disclosure
            taskControl
            OutlineField(id: row.id, text: row.text, isRoot: row.depth == 0,
                         focusRequest: $focusRequest, handlers: handlers,
                         fontSize: fontSize,
                         accessibilityDetails: NodeSpeech.details(NodeSpeech.facts(of: row)))
            if let progress = row.taskProgress {
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(L("%@ von %@ Aufgaben erledigt", "\(progress.done)", "\(progress.total)"))
            }
            ForEach(row.tags.prefix(3), id: \.self) { tag in
                Circle()
                    .fill(Color(hex: tagCatalog.hex(for: tag)))
                    .frame(width: 8, height: 8)
                    .help(tag)
                    .accessibilityLabel(Text(verbatim: tag))
            }
            if row.tags.count > 3 {
                Text("+\(row.tags.count - 3)").font(.caption2).foregroundStyle(.secondary)
            }
            if row.hasLink {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Hat einen Link")
                    .accessibilityLabel(Text("Hat einen Link"))
            }
            if row.hasNote {
                Button {
                    handlers.openNote(row.id)
                } label: {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Notiz öffnen (⌥ ⌘ N)")
                .accessibilityLabel(Text("Notiz öffnen"))
            }
            if row.depth > 0 {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .opacity(hovering || isSelected ? 1 : 0)
                    .help("Ziehen: obere Hälfte einer Zeile = davor, Mitte = hinein, untere Hälfte = danach")
                    .accessibilityHidden(true)
                    .onDrag {
                        draggedRow = row.id
                        return NSItemProvider(object: row.id.uuidString as NSString)
                    }
            }
        }
        .padding(.leading, indent + 4)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22)
                      : matchState == .current ? Color.orange.opacity(0.3)
                      : matchState == .match ? Color.yellow.opacity(0.25) : Color.clear))
        .opacity(isDimmed ? 0.35 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor, lineWidth: indicator == .inside ? 2 : 0))
        .overlay(alignment: .topLeading) { dropLine }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu { MenuEntriesView(entries: handlers.contextMenu(row.id)) }
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { newHeight in
            height = newHeight
        }
        .onDrop(of: [.text], delegate: OutlineDropDelegate(target: row.id,
                                                            rowHeight: height,
                                                            dragged: $draggedRow,
                                                            indicator: $dropIndicator,
                                                            handlers: handlers))
    }

    /// Kästchen einer Aufgabe (ausgefüllt / halb / leer).
    @ViewBuilder
    private var taskControl: some View {
        if row.taskStatus != nil && (row.taskProgress == nil || row.hasTaskMark) {
            Button {
                handlers.toggleDone(row.id)
            } label: {
                Image(systemName: taskSymbol)
                    .foregroundStyle(row.taskStatus == .open ? Color.secondary : Color.accentColor)
                    .frame(width: 16, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Abhaken (⇧ ⌘ D)")
            .accessibilityLabel(row.taskStatus == .done ? L("Wieder öffnen") : L("Abhaken"))
        }
    }

    private var taskSymbol: String {
        switch row.taskStatus {
        case .done?: return "checkmark.square.fill"
        case .partial?: return "minus.square"
        default: return "square"
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.hasChildren && row.depth > 0 {
            Button {
                handlers.toggleCollapsed(row.id)
            } label: {
                Image(systemName: row.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .frame(width: 14, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.isCollapsed ? L("Aufklappen (⌘ .)") : L("Einklappen (⌘ .)"))
            .accessibilityLabel(row.isCollapsed ? L("Aufklappen") : L("Einklappen"))
        } else {
            Color.clear.frame(width: 14, height: 1)
        }
    }

    /// Blaue Linie über oder unter der Zeile, solange ein Knoten davor/danach abgelegt würde.
    @ViewBuilder
    private var dropLine: some View {
        if let position = indicator, position != .inside {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, indent + 20)
                .frame(maxHeight: .infinity, alignment: position == .after ? .bottom : .top)
                .allowsHitTesting(false)
        }
    }
}

/// Nimmt einen gezogenen Knoten an: oberes Drittel = davor, Mitte = hinein, unteres Drittel = danach.
struct OutlineDropDelegate: DropDelegate {
    let target: UUID
    let rowHeight: CGFloat
    @Binding var dragged: UUID?
    @Binding var indicator: OutlineDropIndicator?
    let handlers: OutlineHandlers

    private func position(_ info: DropInfo) -> OutlineDropPosition {
        let y = info.location.y
        if y < rowHeight / 3 { return .before }
        if y > rowHeight * 2 / 3 { return .after }
        return .inside
    }

    /// Die gewünschte Position – oder, wenn die nicht geht, „hinein“ als Ausweichziel (z. B. beim Hauptknoten).
    private func resolvedPosition(_ info: DropInfo) -> OutlineDropPosition? {
        guard let dragged else { return nil }
        let wanted = position(info)
        if handlers.canMove(dragged, target, wanted) { return wanted }
        if wanted != .inside && handlers.canMove(dragged, target, .inside) { return .inside }
        return nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        resolvedPosition(info) != nil
    }

    func dropEntered(info: DropInfo) {
        updateIndicator(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateIndicator(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if indicator?.target == target { indicator = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        indicator = nil
        defer { dragged = nil }
        guard let dragged, let position = resolvedPosition(info) else { return false }
        handlers.move(dragged, target, position)
        return true
    }

    private func updateIndicator(_ info: DropInfo) {
        guard let position = resolvedPosition(info) else {
            if indicator?.target == target { indicator = nil }
            return
        }
        let new = OutlineDropIndicator(target: target, position: position)
        if indicator != new { indicator = new }
    }
}
