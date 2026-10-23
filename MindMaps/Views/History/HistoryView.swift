import SwiftUI

/// Ablage › Verlauf … (M10): frühere Fassungen ansehen und ganz oder zweigweise zurückholen.
/// Links die Zeitleiste, rechts die Vorschau der gewählten Fassung und ihre Knoten.
/// Beides läuft über `DocumentActions` und lässt sich mit ⌘Z zurücknehmen.
struct HistoryView: View {
    @ObservedObject var document: MindMapFile
    let undoManager: UndoManager?
    /// Nach dem Wiederherstellen: ID des zurückgeholten Zweigs (bzw. `nil` bei einer ganzen Fassung).
    let onRestore: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var entryID: String?
    @State private var nodeID: UUID?
    @State private var loaded: (id: String, data: MindMapDocumentData)?

    private var entries: [HistoryEntry] { document.history.entries }
    private var entry: HistoryEntry? { entries.first { $0.id == entryID } }

    /// Inhalt der gewählten Fassung (einmal entpackt, dann gemerkt).
    private var version: MindMapDocumentData? {
        guard let entry else { return nil }
        if let loaded, loaded.id == entry.id { return loaded.data }
        return document.historyDocument(entry)
    }

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Noch kein Verlauf", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Beim Sichern entsteht höchstens alle 10 Minuten ein Zwischenstand – sobald sich etwas geändert hat.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    timeline
                        .frame(width: 230)
                    Divider()
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 860, idealWidth: 960, minHeight: 560, idealHeight: 640)
        .onAppear {
            if entryID == nil { entryID = entries.first?.id }
            load()
        }
        .onChange(of: entryID) { _, _ in
            nodeID = nil
            load()
        }
    }

    private func load() {
        guard let entry, loaded?.id != entry.id, let data = document.historyDocument(entry) else { return }
        loaded = (entry.id, data)
    }

    // MARK: - Zeitleiste

    private var timeline: some View {
        List(selection: $entryID) {
            ForEach(Self.days(entries)) { group in
                Section(Self.dayTitle(group.day)) {
                    ForEach(group.entries) { entry in
                        HStack {
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .monospacedDigit()
                            Spacer()
                            Text(entry.nodeCount == 1 ? L("1 Knoten") : L("%@ Knoten", "\(entry.nodeCount)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(entry.id)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    struct DayGroup: Identifiable {
        let day: Date
        var entries: [HistoryEntry]
        var id: Date { day }
    }

    /// Zwischenstände nach Tagen (neueste zuerst).
    static func days(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [DayGroup] {
        var result: [DayGroup] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            let day = calendar.startOfDay(for: entry.date)
            if let last = result.indices.last, result[last].day == day {
                result[last].entries.append(entry)
            } else {
                result.append(DayGroup(day: day, entries: [entry]))
            }
        }
        return result
    }

    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return L("Heute") }
        if calendar.isDateInYesterday(day) { return L("Gestern") }
        return day.formatted(date: .complete, time: .omitted)
    }

    // MARK: - Vorschau und Knoten

    @ViewBuilder
    private var detail: some View {
        if let version {
            let removed = DocumentHistory.removedSince(version.root, current: document.data.root)
            VStack(spacing: 0) {
                MapThumbnailView(root: version.root, theme: ThemeStore.theme(for: version),
                                 dark: colorScheme == .dark, images: AssetImages(document.assets),
                                 connections: version.connections, style: version.style,
                                 selection: nodeID, marked: removed,
                                 onSelect: { id in nodeID = id })
                    .frame(height: 280)
                    .accessibilityLabel(Text("Vorschau der Fassung"))
                Divider()
                nodeList(version.root, removed: removed)
                    .frame(maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView("Fassung nicht lesbar", systemImage: "exclamationmark.triangle")
        }
    }

    private func nodeList(_ root: Node, removed: Set<UUID>) -> some View {
        List(selection: $nodeID) {
            ForEach(Self.rows(root)) { row in
                HStack(spacing: 6) {
                    Text(NodeSpeech.label(row.node.text))
                        .lineLimit(1)
                        .padding(.leading, CGFloat(row.depth) * 16)
                    if !row.node.children.isEmpty {
                        Text(L("%@ darunter", "\(row.node.nodeCount - 1)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if removed.contains(row.node.id) {
                        Text("fehlt heute")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.yellow.opacity(0.35)))
                    }
                }
                .tag(row.node.id)
                .accessibilityElement(children: .combine)
            }
        }
    }

    struct Row: Identifiable {
        let node: Node
        let depth: Int
        var id: UUID { node.id }
    }

    /// Alle Knoten der Fassung in Lesereihenfolge mit ihrer Ebene.
    static func rows(_ root: Node) -> [Row] {
        var result: [Row] = []
        func visit(_ node: Node, _ depth: Int) {
            result.append(Row(node: node, depth: depth))
            node.children.forEach { visit($0, depth + 1) }
        }
        visit(root, 0)
        return result
    }

    // MARK: - Knöpfe

    private var footer: some View {
        HStack {
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Schließen") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Zweig wiederherstellen", action: restoreBranch)
                .disabled(version == nil || nodeID == nil || nodeID == version?.root.id)
                .help(Text("Holt den ausgewählten Zweig aus dieser Fassung zurück – der Rest der Map bleibt."))
            Button("Diese Fassung wiederherstellen", action: restoreVersion)
                .disabled(version == nil)
        }
        .padding(16)
    }

    private var summary: String {
        guard let entry else {
            return entries.isEmpty ? "" : L("Wähle links einen Zwischenstand.")
        }
        let when = entry.date.formatted(date: .abbreviated, time: .shortened)
        guard let version else { return when }
        let removed = DocumentHistory.removedSince(version.root, current: document.data.root).count
        if removed == 0 { return L("Fassung vom %@ – alle Knoten gibt es noch.", when) }
        if removed == 1 { return L("Fassung vom %@ – 1 Knoten fehlt heute (gelb markiert).", when) }
        return L("Fassung vom %@ – %@ Knoten fehlen heute (gelb markiert).", when, "\(removed)")
    }

    private func restoreVersion() {
        guard let entry, let version else { return }
        DocumentActions(document: document, undoManager: undoManager).restoreVersion(version, date: entry.date)
        dismiss()
        onRestore(nil)
    }

    private func restoreBranch() {
        guard let version, let nodeID else { return }
        let restored = DocumentActions(document: document, undoManager: undoManager).restoreBranch(nodeID, from: version)
        dismiss()
        onRestore(restored)
    }
}
