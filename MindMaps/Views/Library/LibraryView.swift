import SwiftUI
import AppKit

/// Das Bibliotheksfenster: Seitenleiste (Alle, Zuletzt benutzt, Ordner, Papierkorb),
/// Raster oder Liste, Suche über Titel und Knotentexte, Vorlagen.
struct LibraryView: View {
    static let windowID = "library"

    @AppStorage("libraryPath") private var libraryPath = ""
    @AppStorage("librarySort") private var sort: LibrarySort = .name
    @AppStorage("libraryLayout") private var layout: LibraryLayout = .grid
    @StateObject private var model: LibraryModel
    @Environment(\.openDocument) private var openDocument

    @State private var search = ""
    @State private var selection = Set<URL>()
    @State private var renameTarget: URL?
    @State private var renameText = ""
    @State private var confirmEmptyTrash = false

    init() {
        let stored = UserDefaults.standard.string(forKey: "libraryPath") ?? ""
        _model = StateObject(wrappedValue: LibraryModel(rootURL: LibraryStore.libraryURL(fromStoredPath: stored)))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .searchable(text: $search, placement: .toolbar, prompt: L("Titel oder Knotentext"))
        .toolbar { toolbarContent }
        .onAppear { model.open(LibraryStore.libraryURL(fromStoredPath: libraryPath)) }
        .onChange(of: libraryPath) { _, path in
            model.open(LibraryStore.libraryURL(fromStoredPath: path))
        }
        .onChange(of: model.section) { _, _ in selection = [] }
        .alert("Das hat nicht geklappt", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Umbenennen", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Umbenennen") {
                if let target = renameTarget { model.rename(target, to: renameText) }
                renameTarget = nil
            }
            Button("Abbrechen", role: .cancel) { renameTarget = nil }
        }
    }

    private var title: String {
        if !search.isEmpty { return L("Suche") }
        switch model.section ?? .all {
        case .all: return L("Alle Dokumente")
        case .recent: return L("Zuletzt benutzt")
        case .trash: return L("Papierkorb")
        case .tasks: return L("Aufgaben")
        case .folder(let url): return model.folder(at: url)?.name ?? url.lastPathComponent
        }
    }

    // MARK: - Seitenleiste

    private var sidebar: some View {
        List(selection: $model.section) {
            Section("Bibliothek") {
                Label("Alle Dokumente", systemImage: "square.grid.2x2")
                    .tag(LibrarySection.all)
                Label("Zuletzt benutzt", systemImage: "clock")
                    .tag(LibrarySection.recent)
                Label("Aufgaben", systemImage: "checklist")
                    .badge(model.openTaskCount)
                    .tag(LibrarySection.tasks)
            }
            Section("Ordner") {
                OutlineGroup([model.contents.root], children: \.children) { folder in
                    Label(folder.name, systemImage: folder.path == model.contents.root.path ? "books.vertical" : "folder")
                        .tag(LibrarySection.folder(folder.url))
                        .dropDestination(for: URL.self) { urls, _ in
                            model.drop(urls, into: folder.url)
                        }
                        .contextMenu { folderMenu(folder) }
                }
            }
            Section {
                Label("Papierkorb", systemImage: model.contents.trash.isEmpty ? "trash" : "trash.fill")
                    .badge(model.contents.trash.count)
                    .tag(LibrarySection.trash)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func folderMenu(_ folder: LibraryFolder) -> some View {
        Button("Neues Dokument hier") {
            model.section = .folder(folder.url)
            if let url = model.createDocument(from: .blank) { open(url) }
        }
        Button("Neuer Ordner hier") {
            model.section = .folder(folder.url)
            if let url = model.createFolder() { startRename(url) }
        }
        if folder.path != model.contents.root.path {
            Divider()
            Button("Umbenennen …") { startRename(folder.url) }
            Button("Im Finder zeigen") { model.showInFinder(folder.url) }
            Button("In den Papierkorb", role: .destructive) { model.moveToTrash([folder.url]) }
        } else {
            Button("Im Finder zeigen") { model.showInFinder(folder.url) }
        }
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var detail: some View {
        if model.section == .trash && search.isEmpty {
            TrashView(model: model, confirmEmpty: $confirmEmptyTrash)
        } else if model.section == .tasks && search.isEmpty {
            TasksOverview(model: model, open: { url, id in open(url, node: id) })
        } else {
            let items = model.items(search: search, sort: sort)
            if items.isEmpty {
                emptyState
            } else if layout == .grid {
                grid(items)
            } else {
                table(items)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if model.contents.documents.isEmpty {
            ContentUnavailableView {
                Label("Noch keine Mindmaps", systemImage: "point.3.connected.trianglepath.dotted")
            } description: {
                Text(L("Die Bibliothek liegt in „%@“.", model.rootURL.path))
            } actions: {
                Button("Neues Dokument") { newDocument(.blank) }
                Button("Importieren …") { importIntoLibrary() }
                Button("Beispieldokumente hinzufügen") { model.createSamples() }
            }
        } else {
            ContentUnavailableView("Hier ist nichts", systemImage: "folder",
                                   description: Text("Lege ein Dokument an oder zieh eines hierher."))
        }
    }

    private func grid(_ items: [LibraryItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18)], spacing: 18) {
                ForEach(items) { item in
                    LibraryCard(item: item,
                                isSelected: selection.contains(item.url),
                                subtitle: subtitle(for: item))
                        .onTapGesture(count: 2) { open(item.url) }
                        .onTapGesture { selection = [item.url] }
                        .contextMenu { itemMenu(Set([item.url])) }
                        .draggable(item.url)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard case .folder(let folder) = item else { return false }
                            return model.drop(urls, into: folder.url)
                        }
                }
            }
            .padding(20)
        }
        .onDeleteCommand { trashSelection() }
    }

    /// Spalte bzw. Angabe „Ort“ nur, wenn Dokumente aus verschiedenen Ordnern zu sehen sind (1.1.2).
    private var showsLocation: Bool {
        if case .folder = model.section ?? .all, search.isEmpty { return false }
        return true
    }

    private func table(_ items: [LibraryItem]) -> some View {
        Table(items, selection: $selection) {
            TableColumn(L("Name")) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.document == nil ? "folder" : "doc.richtext")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                        if case .document(_, let match?) = item, match != item.name {
                            Text(L("„%@“", match)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .width(min: 180, ideal: 340)
            TableColumn(L("Geändert")) { item in
                Text(item.document.map { FriendlyDate.text($0.modified) } ?? "–")
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 160)
            TableColumn(L("Knoten")) { item in
                Text(item.document.map { "\($0.nodeCount)" } ?? "–")
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)
            if showsLocation {
                TableColumn(L("Ort")) { item in
                    Text(model.location(of: item.url)).foregroundStyle(.secondary)
                }
            }
        }
        // Keine leeren, gestreiften Zeilen unter den Einträgen (1.1.2).
        .alternatingRowBackgrounds(.disabled)
        .contextMenu(forSelectionType: URL.self) { urls in
            itemMenu(urls)
        } primaryAction: { urls in
            urls.forEach(open)
        }
        .onDeleteCommand { trashSelection() }
    }

    private func subtitle(for item: LibraryItem) -> String {
        switch item {
        case .folder(let folder):
            let count = folder.children?.count ?? 0
            return count == 0 ? L("Ordner") : L("Ordner · %@ Unterordner", "\(count)")
        case .document(let document, let match):
            if let match, match != document.title { return L("„%@“", match) }
            var parts = [FriendlyDate.text(document.modified),
                         L("%@ Knoten", "\(document.nodeCount)")]
            if showsLocation {
                parts.append(model.location(of: document.url))
            }
            return parts.joined(separator: " · ")
        }
    }

    @ViewBuilder
    private func itemMenu(_ urls: Set<URL>) -> some View {
        let targets = Array(urls)
        if targets.count == 1, let url = targets.first {
            Button("Öffnen") { open(url) }
            Button("Umbenennen …") { startRename(url) }
        }
        if !targets.isEmpty {
            Menu("Bewegen nach") {
                ForEach(model.folderOptions) { option in
                    Button(String(repeating: "    ", count: option.depth) + option.folder.name) {
                        for url in targets { model.move(url, to: option.folder.url) }
                    }
                }
            }
            if targets.count == 1, let url = targets.first {
                Button("Im Finder zeigen") { model.showInFinder(url) }
            }
            Divider()
            Button("In den Papierkorb", role: .destructive) {
                model.moveToTrash(targets)
                selection = []
            }
        }
    }

    // MARK: - Werkzeugleiste

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(DocumentTemplate.allCases) { template in
                    Button {
                        newDocument(template)
                    } label: {
                        Label(template.title, systemImage: template.symbol)
                    }
                }
                Divider()
                Button("Importieren …") { importIntoLibrary() }
                Button("Anleitung und Lernbeispiele hinzufügen") { model.createLearningSamples() }
                Button("Beispieldokumente hinzufügen") { model.createSamples() }
            } label: {
                Label("Neues Dokument", systemImage: "square.and.pencil")
            } primaryAction: {
                newDocument(.blank)
            }
            .help("Neues Dokument (Klick) oder aus einer Vorlage (Pfeil)")

            Button {
                if let url = model.createFolder() { startRename(url) }
            } label: {
                Label("Neuer Ordner", systemImage: "folder.badge.plus")
            }
            .help("Neuer Ordner im gewählten Ordner")

            Picker("Darstellung", selection: $layout) {
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid)
                Image(systemName: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Raster oder Liste")

            Menu {
                Picker("Sortieren nach", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sortieren", systemImage: "arrow.up.arrow.down")
            }
            .help("Sortieren nach Name oder Änderungsdatum")

            Button {
                trashSelection()
            } label: {
                Label("In den Papierkorb", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
            .help("Auswahl in den Papierkorb der Bibliothek legen (⌫)")
        }
    }

    // MARK: - Aktionen

    private func newDocument(_ template: DocumentTemplate) {
        if let url = model.createDocument(from: template) { open(url) }
    }

    /// Öffnet ein Dokument und wählt dort einen Knoten aus (Aufgaben-Übersicht).
    private func open(_ url: URL, node id: UUID) {
        PendingSelection.set(id, for: url)
        open(url)
    }

    private func open(_ url: URL) {
        if let folder = model.folder(at: url) {
            search = ""
            model.section = .folder(folder.url)
            return
        }
        Task {
            do {
                try await openDocument(at: url)
            } catch {
                model.errorMessage = L("„%@“ ließ sich nicht öffnen: %@", url.deletingPathExtension().lastPathComponent, error.localizedDescription)
            }
        }
    }

    /// Import in den gerade gezeigten Ordner (sonst oberste Ebene der Bibliothek).
    private func importIntoLibrary() {
        ImportController.chooseAndImport(into: model.currentFolder)
        model.refresh()
    }

    private func startRename(_ url: URL) {
        renameText = url.pathExtension == LibraryScanner.documentExtension
            ? url.deletingPathExtension().lastPathComponent
            : url.lastPathComponent
        renameTarget = url
    }

    private func trashSelection() {
        guard !selection.isEmpty else { return }
        model.moveToTrash(Array(selection))
        selection = []
    }
}

/// Karte im Raster: Vorschaubild (bzw. Ordnersymbol), Name, Untertitel.
struct LibraryCard: View {
    let item: LibraryItem
    let isSelected: Bool
    let subtitle: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                switch item {
                case .folder:
                    Rectangle().fill(Color.secondary.opacity(0.08))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                case .document(let document, _):
                    MapThumbnailView(root: document.data.root,
                                     theme: ThemeStore.theme(for: document.data),
                                     dark: colorScheme == .dark,
                                     connections: document.data.connections,
                                     style: document.data.style)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 3 : 1))

            Text(item.name)
                .font(.headline)
                .lineLimit(1)
            // Immer zwei Zeilen Platz – so sind alle Karten gleich hoch (1.1.2).
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .contentShape(Rectangle())
    }
}

/// Papierkorb der Bibliothek: wiederherstellen oder endgültig löschen.
struct TrashView: View {
    @ObservedObject var model: LibraryModel
    @Binding var confirmEmpty: Bool

    var body: some View {
        if model.contents.trash.isEmpty {
            ContentUnavailableView("Der Papierkorb ist leer", systemImage: "trash",
                                   description: Text("Gelöschte Dokumente und Ordner landen zuerst hier und lassen sich wiederherstellen."))
        } else {
            List {
                ForEach(model.contents.trash) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.isFolder ? "folder" : "doc.richtext")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(L("aus „%@“", item.originalFolder.isEmpty ? model.contents.root.name : item.originalFolder))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Wiederherstellen") { model.restore(item) }
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Wiederherstellen") { model.restore(item) }
                        Button("Endgültig löschen", role: .destructive) { model.deletePermanently(item) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Text("Endgültig gelöschte Einträge landen im Papierkorb von macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Papierkorb leeren …", role: .destructive) { confirmEmpty = true }
                }
                .padding(12)
                .background(.bar)
            }
            .confirmationDialog("Papierkorb leeren?", isPresented: $confirmEmpty) {
                Button("Leeren", role: .destructive) { model.emptyTrash() }
            } message: {
                Text("Alle Einträge wandern in den Papierkorb von macOS.")
            }
        }
    }
}

/// Alle offenen Aufgaben der Bibliothek, nach Dokument gruppiert. Doppelklick öffnet die Stelle.
struct TasksOverview: View {
    @ObservedObject var model: LibraryModel
    let open: (URL, UUID) -> Void

    var body: some View {
        let groups = model.documentsWithOpenTasks
        if groups.isEmpty {
            ContentUnavailableView("Keine offenen Aufgaben", systemImage: "checklist.checked",
                                   description: Text("Markiere Knoten mit ⇧ ⌘ T als Aufgabe – sie erscheinen dann hier."))
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            TaskRow(task: task)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { open(group.document.url, task.id) }
                                .contextMenu {
                                    Button("Im Dokument zeigen") { open(group.document.url, task.id) }
                                }
                        }
                    } header: {
                        HStack {
                            Text(group.document.title).font(.headline)
                            Text(model.location(of: group.document.url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L("%@ offen", "\(group.tasks.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct TaskRow: View {
    let task: TaskEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: task.status == .partial ? "minus.square" : "square")
                .foregroundStyle(task.status == .partial ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.text.isEmpty ? L("Ohne Text") : task.text)
                if task.path.count > 1 {
                    Text(task.path.dropFirst().joined(separator: " › "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .help("Doppelklick öffnet die Mindmap an dieser Stelle")
    }
}

/// Datum für die Bibliothek: „Heute, 14:30“, „Gestern, 9:05“, sonst z. B. „25. Sept. 2026, 16:25“ (1.1.2).
enum FriendlyDate {
    static func text(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return L("Heute, %@", time) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return L("Gestern, %@", time)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
