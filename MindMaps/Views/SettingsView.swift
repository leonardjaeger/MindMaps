import SwiftUI
import AppKit

/// Einstellungen (MindMaps › Einstellungen …, ⌘ ,).
struct SettingsView: View {
    var body: some View {
        TabView {
            LibrarySettings()
                .tabItem { Label("Bibliothek", systemImage: "books.vertical") }
            TagSettings()
                .tabItem { Label("Tags", systemImage: "tag") }
            ThemeSettings()
                .tabItem { Label("Themen", systemImage: "paintpalette") }
            AccessibilitySettings()
                .tabItem { Label("Bedienung", systemImage: "accessibility") }
        }
        .frame(width: 540)
    }
}

/// Einstellungen › Bibliothek.
struct LibrarySettings: View {
    @AppStorage("libraryPath") private var libraryPath = ""
    @AppStorage(SpotlightIndexer.enabledKey) private var spotlightEnabled = true
    @State private var choosingFolder = false

    private var libraryURL: URL { LibraryStore.libraryURL(fromStoredPath: libraryPath) }

    var body: some View {
        Form {
            Section("Bibliothek") {
                LabeledContent("Ordner") {
                    Text(libraryURL.path)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Ändern …") { choosingFolder = true }
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
                    }
                    Spacer()
                    Button("Standard wiederherstellen") { libraryPath = "" }
                        .disabled(libraryPath.isEmpty)
                }
                Text("Standard ist „Dokumente/MindMaps“. Beim Wechsel bleiben die Dateien im alten Ordner liegen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Spotlight") {
                Toggle("Mindmaps in Spotlight finden", isOn: $spotlightEnabled)
                Text("⌘ Leertaste findet eine Mindmap dann auch über ein Wort aus einem Knoten oder einer Notiz.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { libraryPath = url.path }
        }
        .onChange(of: spotlightEnabled) { _, enabled in
            if enabled {
                SpotlightIndexer.update(MindMapCatalog.libraryDocuments())
            } else {
                SpotlightIndexer.removeAll()
            }
        }
    }
}

/// Einstellungen › Tags: Farben ändern, Tags anlegen und aus dem Katalog entfernen.
/// Tags in Dokumenten bleiben erhalten; ohne Katalogeintrag bekommen sie eine feste Farbe.
struct TagSettings: View {
    @AppStorage(TagStore.key) private var tagJSON = ""
    @State private var newTag = ""

    private var catalog: TagCatalog { TagStore.decode(tagJSON) }

    var body: some View {
        Form {
            Section {
                ForEach(catalog.tags) { tag in
                    HStack {
                        Circle().fill(Color(hex: catalog.hex(for: tag.name))).frame(width: 12, height: 12)
                        Text(tag.name)
                        Spacer()
                        Picker("Farbe", selection: colorBinding(tag.name)) {
                            ForEach(TagCatalog.colors.indices, id: \.self) { index in
                                Text(TagCatalog.colors[index].name).tag(index)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button(role: .destructive) {
                            update { $0.tags.removeAll { $0.name == tag.name } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Aus der Liste entfernen")
                    }
                }
                HStack {
                    TextField("Neues Tag", text: $newTag).onSubmit(add)
                    Button("Hinzufügen", action: add)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Tags für alle Dokumente")
            } footer: {
                Text("Die ersten sieben Tags setzt du mit ⌥ ⌘ 1 bis ⌥ ⌘ 7.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Vorgaben wiederherstellen") { tagJSON = "" }
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ name: String) -> Binding<Int> {
        Binding(get: { catalog.definition(named: name)?.color ?? 0 },
                set: { color in
                    update { catalog in
                        if let index = catalog.tags.firstIndex(where: { $0.name == name }) {
                            catalog.tags[index].color = color
                        }
                    }
                })
    }

    private func add() {
        update { _ = $0.add(newTag) }
        newTag = ""
    }

    private func update(_ change: (inout TagCatalog) -> Void) {
        var catalog = self.catalog
        change(&catalog)
        tagJSON = TagStore.encode(catalog)
    }
}

/// Einstellungen › Themen: eigene Themen umbenennen, exportieren, importieren und löschen (M8).
struct ThemeSettings: View {
    @AppStorage(ThemeLibrary.key) private var libraryJSON = ""
    @State private var message: String?

    private var themes: [Theme] { ThemeLibrary.decode(libraryJSON) }

    var body: some View {
        Form {
            Section {
                if themes.isEmpty {
                    Text("Noch keine eigenen Themen. Im Dokument: Seitenleiste › Thema › „Als eigenes Thema sichern …“.")
                        .foregroundStyle(.secondary)
                }
                ForEach(themes) { theme in
                    HStack {
                        HStack(spacing: 2) {
                            ForEach(Array(theme.light.branches.prefix(6).enumerated()), id: \.offset) { _, hex in
                                Circle().fill(Color(hex: hex)).frame(width: 9, height: 9)
                            }
                        }
                        Text(theme.name)
                        Spacer()
                        Button("Umbenennen …") { rename(theme) }
                            .buttonStyle(.borderless)
                        Button("Exportieren …") {
                            ThemeFiles.export(theme) { result in message = result }
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            delete(theme)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Löschen")
                    }
                }
            } header: {
                Text("Eigene Themen")
            } footer: {
                Text("Dokumente behalten ihr Thema auch dann, wenn es hier gelöscht wird – es ist in ihnen mitgespeichert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Thema importieren …", action: importTheme)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func rename(_ theme: Theme) {
        guard let name = TextPrompt.run(title: L("Thema umbenennen"), message: L("Neuer Name:"), initial: theme.name) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = themes
        if let index = list.firstIndex(where: { $0.id == theme.id }) { list[index].name = trimmed }
        libraryJSON = ThemeLibrary.encode(list)
    }

    private func delete(_ theme: Theme) {
        let alert = NSAlert()
        alert.messageText = L("„%@“ löschen?", theme.name)
        alert.informativeText = L("Dokumente, die das Thema verwenden, behalten ihr Aussehen.")
        alert.addButton(withTitle: L("Löschen"))
        alert.addButton(withTitle: L("Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        libraryJSON = ThemeLibrary.encode(themes.filter { $0.id != theme.id })
    }

    private func importTheme() {
        guard let result = ThemeFiles.chooseAndImport() else { return }
        switch result {
        case .success(let theme):
            var list = themes
            if let index = list.firstIndex(where: { $0.id == theme.id }) { list[index] = theme } else { list.append(theme) }
            libraryJSON = ThemeLibrary.encode(list)
            message = L("„%@“ importiert.", theme.name)
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

/// Textgröße in Gliederung und Seitenleiste (M12). macOS gibt anderen Apps seine eigene
/// Textgröße nicht weiter – deshalb eine eigene Einstellung.
enum InterfaceTextSize: String, CaseIterable, Identifiable {
    case standard, large, extraLarge

    static let key = "interfaceTextSize"

    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .standard: return 13
        case .large: return 16
        case .extraLarge: return 20
        }
    }

    var title: String {
        switch self {
        case .standard: return L("Standard")
        case .large: return L("Groß")
        case .extraLarge: return L("Sehr groß")
        }
    }
}

/// Einstellungen › Bedienung: Textgröße, Hinweise zu VoiceOver und Kontrast (M12).
struct AccessibilitySettings: View {
    @AppStorage(InterfaceTextSize.key) private var textSize: InterfaceTextSize = .standard

    var body: some View {
        Form {
            Section("Textgröße") {
                Picker("Gliederung und Seitenleiste", selection: $textSize) {
                    ForEach(InterfaceTextSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                Text("Die Mindmap selbst vergrößerst du mit ⌘ + (oder mit zwei Fingern auf dem Trackpad).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("VoiceOver") {
                Text("VoiceOver liest jeden Knoten mit Ebene, Aufgabe, Notiz und Tags vor – in der Gliederung und in der Map. In der Map wählst du Knoten mit den Pfeiltasten; VoiceOver sagt dann den neuen Knoten an. Weitere Aktionen (Bearbeiten, Unterknoten, Abhaken, Einklappen) findest du im Aktionen-Menü von VoiceOver (VO ⌘ Leertaste).")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Kontrast und Bewegung") {
                Text("Alle eingebauten Themen haben genug Kontrast (WCAG AA). Bei eigenen Farben warnt die Seitenleiste, wenn Text schwer lesbar wird. „Hoher Kontrast“ ist das Thema mit den kräftigsten Farben. Ist in macOS „Bewegung reduzieren“ eingeschaltet, springt die Präsentation ohne Kamerafahrt.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
