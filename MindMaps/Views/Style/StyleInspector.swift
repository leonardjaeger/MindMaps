import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Knoten-Werkzeuge oben in der Werkzeugleiste (1.1.2): Sobald ein Knoten ausgewählt ist, steht dort
/// je ein Knopf mit Popover. Die Seitenleiste (⇧ ⌘ I) zeigt nur noch Themen und Layout der Mindmap.
enum NodeTool: String, CaseIterable, Identifiable {
    case task, tags, note, media, style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .task: return L("Aufgabe")
        case .tags: return L("Tags")
        case .note: return L("Notiz")
        case .media: return L("Link, Bild, Formel")
        case .style: return L("Stil")
        }
    }

    var symbol: String {
        switch self {
        case .task: return "checkmark.square"
        case .tags: return "tag"
        case .note: return "note.text"
        case .media: return "paperclip"
        case .style: return "paintbrush"
        }
    }
}

/// Bereich, den ein Menübefehl zeigen soll (Informationen · Stil · Layout · Thema, M8).
enum InspectorTab: String, CaseIterable, Identifiable {
    case info, style, layout, theme

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return L("Info")
        case .style: return L("Stil")
        case .layout: return L("Layout")
        case .theme: return L("Thema")
        }
    }

    /// Knoten-Werkzeug in der Werkzeugleiste (1.1.2) – `nil`: Seitenleiste (Thema, Layout).
    var nodeTool: NodeTool? {
        switch self {
        case .info: return .task
        case .style: return .style
        case .layout, .theme: return nil
        }
    }

    var symbol: String {
        switch self {
        case .info: return "info.circle"
        case .style: return "paintbrush"
        case .layout: return "rectangle.3.group"
        case .theme: return "paintpalette"
        }
    }
}

// MARK: - Stil des Knotens

/// Bereich „Stil“: Form, Hintergrund, Rahmen, Schrift und Zweigfarbe des ausgewählten Knotens.
/// Scrollt nicht selbst – steht in der Seitenleiste unter den Informationen (1.1.2).
struct NodeStyleSection: View {
    let node: Node
    let depth: Int
    let look: NodeAppearance
    let theme: Theme
    let palette: ThemePalette
    let actions: DocumentActions
    let canPaste: Bool
    let copyStyle: () -> Void
    let pasteStyle: () -> Void

    @State private var borderWidth: Double = 1.5

    private var style: NodeStyle { node.style ?? NodeStyle() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            shapeSection
            Divider()
            nodeSection
            Divider()
            textSection
            Divider()
            branchSection
            Divider()
            clipboardSection
        }
        .onAppear { borderWidth = look.borderWidth }
        .onChange(of: look.borderWidth) { _, value in borderWidth = value }
    }

    // MARK: Form

    private var shapeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Form", systemImage: "square.on.circle").font(.subheadline.weight(.semibold))
                Spacer()
                if style.shape != nil {
                    Button("Wie im Thema") { actions.setShape(nil, of: node.id) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(Theme.NodeShape.allCases, id: \.self) { shape in
                    shapeButton(shape)
                }
            }
        }
    }

    private func shapeButton(_ shape: Theme.NodeShape) -> some View {
        let selected = look.shape == shape
        return Button {
            actions.setShape(shape, of: node.id)
        } label: {
            VStack(spacing: 2) {
                ShapeIcon(shape: shape, color: selected ? .accentColor : .secondary)
                    .frame(width: 38, height: 24)
                Text(shape.title)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(shape.title)
    }

    // MARK: Knoten

    private var nodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Knoten", systemImage: "square.fill.on.square").font(.subheadline.weight(.semibold))
            ColorChooser(title: L("Hintergrund"), hex: look.fill ?? palette.canvas, isCustom: style.fill != nil,
                         suggestions: [palette.nodeFill, "#FFF3BF", "#D3F9D8", "#D0EBFF", "#FFE3E3", "#EDE7F6", palette.rootFill]) { hex in
                actions.updateNodeStyle(node.id, L("Hintergrund ändern")) { $0.fill = hex }
            }
            ColorChooser(title: L("Rahmen"), hex: look.border ?? look.branch, isCustom: style.border != nil,
                         suggestions: Array(palette.branches.prefix(6))) { hex in
                actions.updateNodeStyle(node.id, L("Rahmen ändern")) { $0.border = hex }
            }
            HStack {
                Text("Rahmenstärke")
                Slider(value: $borderWidth, in: NodeStyle.borderWidths, step: 0.5) {
                    Text("Rahmenstärke")
                } onEditingChanged: { editing in
                    if !editing {
                        actions.updateNodeStyle(node.id, L("Rahmenstärke ändern")) { $0.borderWidth = borderWidth }
                    }
                }
                .labelsHidden()
                Text(borderWidth == 0 ? "kein" : String(format: "%.1f", borderWidth))
                    .font(.caption.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            }
            if style.borderWidth != nil {
                Button("Rahmenstärke wie im Thema") {
                    actions.updateNodeStyle(node.id, L("Rahmenstärke ändern")) { $0.borderWidth = nil }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    // MARK: Text

    private var textSection: some View {
        let metrics = NodeMetrics(theme: theme)
        let size = Double(metrics.fontSize(for: node, depth: depth))
        return VStack(alignment: .leading, spacing: 10) {
            Label("Text", systemImage: "textformat").font(.subheadline.weight(.semibold))
            Picker("Schrift", selection: Binding(
                get: { style.font?.rawValue ?? "" },
                set: { value in actions.updateNodeStyle(node.id, L("Schrift ändern")) { $0.font = Theme.Font(rawValue: value) } })) {
                Text(L("Wie im Thema (%@)", theme.font.title)).tag("")
                ForEach(Theme.Font.allCases, id: \.self) { font in
                    Text(font.title).tag(font.rawValue)
                }
            }
            HStack {
                Stepper(value: Binding(
                    get: { size },
                    set: { value in actions.updateNodeStyle(node.id, L("Schriftgröße ändern")) { $0.fontSize = value } }),
                        in: NodeStyle.fontSizes, step: 1) {
                    Text(L("Größe %@ pt", "\(Int(size))"))
                }
                Spacer()
                if style.fontSize != nil {
                    Button("Standard") {
                        actions.updateNodeStyle(node.id, L("Schriftgröße ändern")) { $0.fontSize = nil }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            HStack {
                Toggle("Fett", isOn: Binding(
                    get: { metrics.weight(for: node, depth: depth) == .bold },
                    set: { value in actions.updateNodeStyle(node.id, L("Fett")) { $0.bold = value } }))
                Toggle("Kursiv", isOn: Binding(
                    get: { style.italic ?? false },
                    set: { value in actions.updateNodeStyle(node.id, L("Kursiv")) { $0.italic = value ? true : nil } }))
            }
            .toggleStyle(.button)
            ColorChooser(title: L("Textfarbe"), hex: look.text, isCustom: style.textColor != nil,
                         suggestions: [palette.nodeText, "#000000", "#FFFFFF", "#C2410C", "#0866E3", "#1F8A4C"]) { hex in
                actions.updateNodeStyle(node.id, L("Textfarbe ändern")) { $0.textColor = hex }
            }
            // Barrierefreiheit (M12): Warnung, wenn Text und Fläche zu wenig Kontrast haben.
            if let ratio = ColorContrast.textIssue(look, canvas: palette.canvas) {
                ContrastWarning(text: L("Text schwer lesbar: Kontrast %@ : 1, nötig sind %@ : 1.",
                                        ColorContrast.Issue.format(ratio),
                                        ColorContrast.Issue.format(ColorContrast.textMinimum)))
            }
        }
    }

    // MARK: Zweig

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Zweig", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.subheadline.weight(.semibold))
            ColorChooser(title: L("Zweigfarbe"), hex: look.branch, isCustom: style.branchColor != nil,
                         suggestions: Array(palette.branches.prefix(6)) + ["#1B2330", "#8B8D98"]) { hex in
                actions.updateNodeStyle(node.id, L("Zweigfarbe ändern")) { $0.branchColor = hex }
            }
            Text("Gilt für den Zweig zu diesem Knoten und alle Unterknoten.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Kopieren, Einsetzen

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Stil kopieren", action: copyStyle)
                    .help("In der Map ⌘ C, sonst ⌥ ⌘ C")
                Button("Stil einsetzen", action: pasteStyle)
                    .disabled(!canPaste)
                    .help("⌘ R")
            }
            Button("Stil zurücksetzen") { actions.setNodeStyle(nil, of: node.id, actionName: "Stil zurücksetzen") }
                .disabled(node.style == nil)
            if node.offset != nil {
                Button("Position zurücksetzen") { actions.resetPosition(of: node.id) }
                    .help("Von Hand verschobenen Knoten wieder an seinen Platz im Layout setzen")
            }
        }
    }
}

// MARK: - Layout

/// Bereich „Layout“: Anordnung, Ausrichtung, Zweige, Abstände, von Hand verschobene Knoten.
struct LayoutSection: View {
    let style: MapStyle
    let theme: Theme
    let movedCount: Int
    let actions: DocumentActions

    @State private var thickness: Double = 1
    @State private var levelSpacing: Double = 1
    @State private var siblingSpacing: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            layoutPicker
            if style.layout.hasSides {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ausrichtung").font(.subheadline.weight(.semibold))
                    Picker("Ausrichtung", selection: Binding(
                        get: { style.sides },
                        set: { value in actions.updateMapStyle(L("Ausrichtung ändern")) { $0.sides = value } })) {
                        ForEach(MapStyle.Sides.allCases) { sides in
                            Text(sides.title(for: style.layout)).tag(sides)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            Divider()
            branchSection
            Divider()
            spacingSection
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(movedCount == 0 ? L("Keine Knoten von Hand verschoben.")
                     : L("Von Hand verschobene Knoten: %@", "\(movedCount)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Alle Positionen zurücksetzen") { actions.resetAllPositions() }
                    .disabled(movedCount == 0)
                Text("Knoten frei verschieben: in der Map ziehen und neben einem Knoten loslassen. Auf einem Knoten loslassen hängt ihn dort an.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Layout-Einstellungen zurücksetzen") {
                actions.updateMapStyle(L("Layout zurücksetzen")) { value in
                    value = MapStyle(layout: value.layout, sides: MapStyle.defaultSides(for: value.layout))
                }
            }
            .disabled(style == MapStyle(layout: style.layout, sides: MapStyle.defaultSides(for: style.layout)))
        }
        .onAppear(perform: sync)
        .onChange(of: style) { _, _ in sync() }
    }

    private func sync() {
        thickness = style.branchThickness
        levelSpacing = style.levelSpacing
        siblingSpacing = style.siblingSpacing
    }

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Layout", systemImage: "rectangle.3.group").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(MapStyle.Layout.allCases) { layout in
                    Button {
                        actions.setLayout(layout)
                    } label: {
                        HStack {
                            Image(systemName: layout.symbol)
                            Text(layout.title)
                            Spacer()
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(style.layout == layout ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Beim Wechsel springen von Hand verschobene Knoten an ihren Platz zurück (⌘ Z holt sie wieder).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zweige", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.subheadline.weight(.semibold))
            Picker("Verlauf", selection: Binding(
                get: { style.branchStyle?.rawValue ?? "" },
                set: { value in actions.updateMapStyle(L("Zweige ändern")) { $0.branchStyle = Theme.BranchStyle(rawValue: value) } })) {
                Text(L("Wie im Thema (%@)", theme.branchStyle.title)).tag("")
                ForEach(Theme.BranchStyle.allCases, id: \.self) { value in
                    Text(value.title).tag(value.rawValue)
                }
            }
            Picker("Breite", selection: Binding(
                get: { style.branchWidth?.rawValue ?? "" },
                set: { value in actions.updateMapStyle(L("Zweige ändern")) { $0.branchWidth = Theme.BranchWidth(rawValue: value) } })) {
                Text(L("Wie im Thema (%@)", theme.branchWidth.title)).tag("")
                ForEach(Theme.BranchWidth.allCases, id: \.self) { value in
                    Text(value.title).tag(value.rawValue)
                }
            }
            slider(L("Stärke"), value: $thickness, range: MapStyle.thicknessRange) { value in
                actions.updateMapStyle(L("Zweigstärke ändern")) { $0.branchThickness = value }
            }
        }
    }

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Abstand", systemImage: "arrow.left.and.right.square").font(.subheadline.weight(.semibold))
            slider(L("Zwischen Ebenen"), value: $levelSpacing, range: MapStyle.levelSpacingRange) { value in
                actions.updateMapStyle(L("Abstand ändern")) { $0.levelSpacing = value }
            }
            slider(L("Zwischen Geschwistern"), value: $siblingSpacing, range: MapStyle.siblingSpacingRange) { value in
                actions.updateMapStyle(L("Abstand ändern")) { $0.siblingSpacing = value }
            }
        }
    }

    /// Schieberegler, der erst beim Loslassen übernimmt (ein Rückgängig-Schritt).
    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                        commit: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded())) %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) {
                Text(title)
            } onEditingChanged: { editing in
                if !editing { commit((value.wrappedValue * 20).rounded() / 20) }
            }
            .labelsHidden()
        }
    }
}

// MARK: - Thema

/// Bereich „Thema“: Themen wählen, Farben, Form und Schrift anpassen, eigene Themen sichern,
/// exportieren und importieren.
struct ThemeSection: View {
    let data: MindMapDocumentData
    let actions: DocumentActions

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ThemeLibrary.key) private var libraryJSON = ""
    @State private var message: String?

    private var theme: Theme { ThemeStore.theme(for: data) }
    private var ownThemes: [Theme] { ThemeLibrary.decode(libraryJSON) }
    private var dark: Bool { colorScheme == .dark }

    /// Weicht das Thema des Dokuments vom Original ab?
    private var isModified: Bool {
        guard let custom = data.customTheme else { return false }
        return ThemeStore.original(withID: data.themeID) != custom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            themeGrid
            Divider()
            customizeSection
            Divider()
            fileSection
        }
    }

    // MARK: Auswahl

    private var themeGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Themen", systemImage: "paintpalette").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ThemeStore.catalog.themes) { item in
                    ThemeCard(theme: item, dark: dark, isSelected: data.themeID == item.id) {
                        actions.setTheme(item.id)
                    }
                }
                ForEach(ownThemes) { item in
                    ThemeCard(theme: item, dark: dark, isSelected: data.themeID == item.id) {
                        actions.applyTheme(item)
                    }
                    .contextMenu {
                        Button("Exportieren …") { export(item) }
                        Button("Aus „Eigene Themen“ löschen", role: .destructive) { delete(item) }
                    }
                }
            }
            if isModified {
                HStack {
                    Text(L("„%@“ ist angepasst.", theme.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Verwerfen") { actions.revertTheme() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: Anpassen

    private var customizeSection: some View {
        let palette = theme.palette(dark: dark)
        return VStack(alignment: .leading, spacing: 10) {
            Label(dark ? L("Farben (dunkles Erscheinungsbild)") : L("Farben (helles Erscheinungsbild)"),
                  systemImage: "swatchpalette").font(.subheadline.weight(.semibold))
            // Farben unter der Beschriftung – nebeneinander passten sie nicht in die Seitenleiste (1.1.2).
            VStack(alignment: .leading, spacing: 4) {
                Text("Zweige")
                HStack(spacing: 4) {
                    ForEach(Array(palette.branches.enumerated()), id: \.offset) { index, hex in
                        DebouncedColorWell(title: L("Zweigfarbe %@", "\(index + 1)"), hex: hex) { value in
                            updatePalette { $0.branches[index] = value }
                        }
                        .frame(width: 30)
                    }
                }
            }
            colorRow(L("Hintergrund"), palette.canvas) { value in updatePalette { $0.canvas = value } }
            colorRow(L("Hauptknoten"), palette.rootFill) { value in updatePalette { $0.rootFill = value } }
            colorRow(L("Text im Hauptknoten"), palette.rootText) { value in updatePalette { $0.rootText = value } }
            colorRow(L("Knoten"), palette.nodeFill) { value in updatePalette { $0.nodeFill = value } }
            colorRow(L("Text"), palette.nodeText) { value in updatePalette { $0.nodeText = value } }
            // Barrierefreiheit (M12): zu schwache Kontraste des Themas anzeigen.
            let issues = ColorContrast.issues(in: theme).filter { $0.dark == dark }
            if !issues.isEmpty {
                ContrastWarning(text: L("Schwacher Kontrast – schwer lesbar für manche Menschen:") + "\n"
                                + issues.map { "• " + $0.description }.joined(separator: "\n"))
            }

            Picker("Form", selection: Binding(
                get: { theme.nodeShape },
                set: { value in actions.updateTheme(L("Form des Themas ändern")) { $0.nodeShape = value } })) {
                ForEach(Theme.NodeShape.allCases, id: \.self) { shape in
                    Text(shape.title).tag(shape)
                }
            }
            Picker("Füllung", selection: Binding(
                get: { theme.nodeFill },
                set: { value in actions.updateTheme(L("Füllung ändern")) { $0.nodeFill = value } })) {
                ForEach(Theme.NodeFillMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Picker("Schrift", selection: Binding(
                get: { theme.font },
                set: { value in actions.updateTheme(L("Schrift ändern")) { $0.font = value } })) {
                ForEach(Theme.Font.allCases, id: \.self) { font in
                    Text(font.title).tag(font)
                }
            }
            Text("Zweige (Verlauf, Breite, Stärke) stellst du weiter unten bei „Layout“ ein – beim Sichern kommen sie mit ins Thema.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func colorRow(_ title: String, _ hex: String, onCommit: @escaping (String) -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            DebouncedColorWell(title: title, hex: hex, onCommit: onCommit)
                .frame(width: 44)
        }
    }

    private func updatePalette(_ change: @escaping (inout ThemePalette) -> Void) {
        let isDark = dark
        actions.updateTheme(L("Farbe des Themas ändern")) { theme in
            if isDark { change(&theme.dark) } else { change(&theme.light) }
        }
    }

    // MARK: Sichern, Export, Import

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Eigene Themen", systemImage: "square.and.arrow.down.on.square").font(.subheadline.weight(.semibold))
            Button("Als eigenes Thema sichern …", action: saveAsOwnTheme)
                .help("Farben, Form, Schrift und Zweige dieser Map als Thema für andere Dokumente sichern")
            HStack {
                Button("Exportieren …") { export(currentStyleAsTheme()) }
                Button("Importieren …", action: importTheme)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Das aktuelle Aussehen als Thema: Thema des Dokuments plus Zweig-Einstellungen aus „Layout“.
    private func currentStyleAsTheme() -> Theme {
        var result = theme
        result.branchStyle = data.style.effectiveBranchStyle(theme)
        result.branchWidth = data.style.effectiveBranchWidth(theme)
        return result
    }

    private func saveAsOwnTheme() {
        let suggestion = data.customTheme == nil ? L("%@ (eigen)", theme.name) : theme.name
        guard let name = TextPrompt.run(title: L("Eigenes Thema sichern"),
                                        message: L("Unter welchem Namen? Das Thema steht danach bei allen Dokumenten zur Auswahl."),
                                        initial: suggestion) else { return }
        let own = ThemeLibrary.makeTheme(from: currentStyleAsTheme(), name: name)
        var list = ThemeLibrary.decode(libraryJSON)
        list.append(own)
        libraryJSON = ThemeLibrary.encode(list)
        actions.applyTheme(own)
        message = L("„%@“ ist gesichert und diesem Dokument zugewiesen.", own.name)
    }

    private func delete(_ item: Theme) {
        let alert = NSAlert()
        alert.messageText = L("„%@“ aus „Eigene Themen“ löschen?", item.name)
        alert.informativeText = L("Dokumente, die das Thema verwenden, behalten ihr Aussehen – es ist in ihnen mitgespeichert.")
        alert.addButton(withTitle: L("Löschen"))
        alert.addButton(withTitle: L("Abbrechen"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        libraryJSON = ThemeLibrary.encode(ThemeLibrary.decode(libraryJSON).filter { $0.id != item.id })
    }

    private func export(_ item: Theme) {
        ThemeFiles.export(item) { result in message = result }
    }

    private func importTheme() {
        guard let imported = ThemeFiles.chooseAndImport() else { return }
        switch imported {
        case .success(let own):
            var list = ThemeLibrary.decode(libraryJSON)
            if let index = list.firstIndex(where: { $0.id == own.id }) { list[index] = own } else { list.append(own) }
            libraryJSON = ThemeLibrary.encode(list)
            actions.applyTheme(own)
            message = L("„%@“ ist importiert und diesem Dokument zugewiesen.", own.name)
        case .failure(let error):
            message = error.localizedDescription
        }
    }
}

/// Theme-Dateien (`.mindmapstheme`) sichern und öffnen.
enum ThemeFiles {
    static var contentType: UTType {
        UTType(filenameExtension: ThemeLibrary.fileExtension, conformingTo: .json) ?? .json
    }

    @MainActor
    static func export(_ theme: Theme, done: (String) -> Void) {
        let panel = NSSavePanel()
        panel.title = L("Thema exportieren")
        panel.nameFieldStringValue = theme.name + "." + ThemeLibrary.fileExtension
        panel.allowedContentTypes = [contentType]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ThemeLibrary.fileData(for: theme).write(to: url, options: .atomic)
            done(L("Gesichert als „%@“ – zum Weitergeben oder auf einem anderen Mac importieren.", url.lastPathComponent))
        } catch {
            done(error.localizedDescription)
        }
    }

    @MainActor
    static func chooseAndImport() -> Result<Theme, Error>? {
        let panel = NSOpenPanel()
        panel.title = L("Thema importieren")
        panel.prompt = L("Importieren")
        panel.allowedContentTypes = [contentType, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Result { try ThemeLibrary.theme(fromFile: Data(contentsOf: url)) }
    }
}

/// Kachel eines Themas: Hintergrund, Hauptknoten und Zweigfarben.
struct ThemeCard: View {
    let theme: Theme
    let dark: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let palette = theme.palette(dark: dark)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(hex: palette.canvas))
                    HStack(spacing: 3) {
                        ForEach(Array(palette.branches.prefix(6).enumerated()), id: \.offset) { _, hex in
                            Capsule().fill(Color(hex: hex)).frame(width: 5, height: 16)
                        }
                    }
                    .offset(x: 18)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: palette.rootFill))
                        .frame(width: 26, height: 12)
                        .offset(x: -30)
                }
                .frame(height: 34)
                Text(theme.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(theme.description)
    }
}

/// Hinweis auf zu schwachen Kontrast (M12).
struct ContrastWarning: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .accessibilityElement(children: .combine)
    }
}
