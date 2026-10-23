import SwiftUI
import AppKit

/// Aufgabe, Tags, Link/Bild/Formel und Notiz des ausgewählten Knotens.
/// Seit 1.1.2 einzeln als Popover aus der Werkzeugleiste (`part`), nicht mehr in der Seitenleiste.
struct NodeInspector: View {
    /// Welcher Teil gezeigt wird.
    enum Part { case all, task, tags, media }

    let node: Node?
    var part: Part = .all
    let isRoot: Bool
    let actions: DocumentActions
    /// Wird hochgezählt, wenn die Notiz den Cursor bekommen soll (Knoten › Notiz bearbeiten).
    let noteFocusToken: Int
    /// Knoten, dessen Notiz beim Erscheinen gleich den Cursor bekommen soll.
    let noteFocusNode: UUID?
    // M7
    var images: AssetImages = .empty
    var fileURL: URL?
    var openLink: (String) -> Void = { _ in }

    @AppStorage(TagStore.key) private var tagJSON = ""
    @State private var newTag = ""

    private var catalog: TagCatalog { TagStore.decode(tagJSON) }

    var body: some View {
        if let node, part != .all {
            switch part {
            case .task: taskSection(node)
            case .tags: tagSection(node)
            case .media:
                NodeMediaSection(node: node, images: images, fileURL: fileURL,
                                 actions: actions, openLink: openLink)
                    .id(node.id)
            case .all: EmptyView()
            }
        } else if let node {
            VStack(alignment: .leading, spacing: 14) {
                Text(node.text.isEmpty ? L("Ohne Text") : node.text)
                    .font(.headline)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                taskSection(node)
                Divider()
                tagSection(node)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label("Notiz", systemImage: "note.text").font(.subheadline.weight(.semibold))
                    NoteEditorView(markdown: node.note,
                                   onCommit: { actions.setNote($0, of: node.id) },
                                   focusOnAppear: noteFocusNode == node.id,
                                   focusToken: noteFocusToken)
                        .id(node.id)
                        .frame(height: 200)
                }
                Divider()
                NodeMediaSection(node: node, images: images, fileURL: fileURL,
                                 actions: actions, openLink: openLink)
                    .id(node.id)
            }
        } else {
            ContentUnavailableView("Kein Knoten ausgewählt", systemImage: "cursorarrow.click",
                                   description: Text("Wähle einen Knoten, um Aufgabe, Tags und Notiz zu sehen."))
        }
    }

    // MARK: - Aufgabe

    @ViewBuilder
    private func taskSection(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Aufgabe", systemImage: "checkmark.square").font(.subheadline.weight(.semibold))
            Toggle("Als Aufgabe markieren", isOn: Binding(
                get: { node.task != nil },
                set: { _ in actions.toggleTask(node.id) }))
                .help("⇧ ⌘ T")
            if node.task != nil || node.hasTaskDescendants {
                Toggle(node.hasTaskDescendants ? L("Alles darunter erledigt") : L("Erledigt"), isOn: Binding(
                    get: { node.taskStatus == .done },
                    set: { _ in actions.toggleDone(node.id) }))
                    .help("⇧ ⌘ D")
            }
            if node.hasTaskDescendants {
                let progress = node.taskProgress
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                Text(L("%@ von %@ Aufgaben erledigt – %@", "\(progress.done)", "\(progress.total)", node.taskStatus?.title ?? L("offen")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private func tagSection(_ node: Node) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tags", systemImage: "tag").font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 6) {
                ForEach(catalog.ordered(including: node.tags), id: \.self) { tag in
                    TagChip(name: tag, hex: catalog.hex(for: tag), isOn: node.tags.contains(tag)) {
                        actions.toggleTag(tag, on: node.id)
                    }
                }
            }
            HStack {
                TextField("Neues Tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button("Hinzufügen", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addTag() {
        guard let node else { return }
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = catalog
        if updated.add(name) { tagJSON = TagStore.encode(updated) }
        if !node.tags.contains(name) { actions.toggleTag(name, on: node.id) }
        newTag = ""
    }
}

/// Tag zum Anklicken: ausgefüllt = gesetzt.
struct TagChip: View {
    let name: String
    let hex: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(isOn ? Color.white : Color(hex: hex))
                .background(Capsule().fill(isOn ? Color(hex: hex) : Color(hex: hex).opacity(0.12)))
                .overlay(Capsule().stroke(Color(hex: hex), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(isOn ? L("Tag entfernen") : L("Tag setzen"))
    }
}

/// Einfacher Zeilenumbruch-Layout für Tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 280
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: maxX, height: y + rowHeight), points)
    }
}

/// Link, Bild und Formel des Knotens (M7).
struct NodeMediaSection: View {
    let node: Node
    let images: AssetImages
    let fileURL: URL?
    let actions: DocumentActions
    let openLink: (String) -> Void

    @State private var link = ""
    @State private var formula = ""
    @State private var imageWidth: Double = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Link", systemImage: "link").font(.subheadline.weight(.semibold))
                HStack {
                    TextField("https:// oder Knoten-Link", text: $link)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { actions.setLink(link, of: node.id) }
                    Button {
                        openLink(node.link)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .help("Link öffnen")
                    .disabled(node.link.isEmpty)
                }
                // Lesbarer Name für Links auf eine PDF-Stelle (1.3).
                if ExternalNodeRequest.isPassageLink(node.link) {
                    Label("PDF-Stelle in MintMarkPDF", systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Link zu diesem Knoten kopieren") {
                    guard let fileURL else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(DocumentLink.make(file: fileURL, node: node.id), forType: .string)
                }
                .disabled(fileURL == nil)
                .help(fileURL == nil ? L("Erst das Dokument sichern") : L("In einen anderen Knoten als Link einfügen"))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Bild", systemImage: "photo").font(.subheadline.weight(.semibold))
                if let image = node.image {
                    if let picture = images.image(image.asset) {
                        Image(nsImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    // Erst beim Loslassen übernehmen – ein Rückgängig-Schritt statt vieler.
                    Slider(value: $imageWidth, in: NodeImage.minWidth...NodeImage.maxWidth) {
                        Text("Breite")
                    } onEditingChanged: { editing in
                        if !editing { actions.resizeImage(of: node.id, toWidth: imageWidth) }
                    }
                    HStack {
                        Button("Ersetzen …") { choose() }
                        Button("Entfernen", role: .destructive) { actions.removeImage(of: node.id) }
                    }
                } else {
                    Button("Bild wählen …") { choose() }
                    Text("Oder ein Bild aus dem Finder oder aus Fotos auf den Knoten ziehen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Formel (LaTeX)", systemImage: "function").font(.subheadline.weight(.semibold))
                TextField("z. B. F = G \\frac{m_1 m_2}{r^2}", text: $formula, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { actions.setFormula(formula, of: node.id) }
                if !formula.trimmingCharacters(in: .whitespaces).isEmpty {
                    FormulaPreview(source: formula)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Übernehmen") { actions.setFormula(formula, of: node.id) }
                        .disabled(formula == node.formula)
                    if !node.formula.isEmpty {
                        Button("Entfernen", role: .destructive) { actions.setFormula("", of: node.id) }
                    }
                }
            }
        }
        .onAppear {
            link = node.link
            formula = node.formula
            imageWidth = node.image?.width ?? 220
        }
        .onChange(of: node.image?.width) { _, value in imageWidth = value ?? 220 }
        .onChange(of: node.link) { _, value in link = value }
        .onChange(of: node.formula) { _, value in formula = value }
    }

    private func choose() {
        guard let data = ImageImport.chooseFile() else { return }
        actions.insertImage(data, into: node.id)
    }
}

/// Vorschau einer Formel (gleicher Satz wie in der Map).
struct FormulaPreview: View {
    let source: String

    var body: some View {
        let box = MathTypesetter.layout(source)
        Canvas { context, _ in
            MathTypesetter.draw(box, in: &context, origin: CGPoint(x: 2, y: box.ascent + 2), color: .primary)
        }
        .frame(width: box.width + 4, height: box.height + 4)
    }
}
