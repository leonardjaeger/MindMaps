import AppIntents
import AppKit
import UniformTypeIdentifiers

// Kurzbefehle und Siri (M9). Die Aktionen erscheinen in der Kurzbefehle-App unter „MindMaps“,
// sobald die App einmal gestartet wurde.

// MARK: - Dokument als Parameter

/// Eine Mindmap-Datei, wie Kurzbefehle sie sehen.
struct MindMapEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mindmap"
    static let defaultQuery = MindMapQuery()

    /// Pfad der Datei.
    let id: String
    let title: String
    /// Ordner in der Bibliothek, z. B. „Studium › Biologie“.
    let location: String

    var url: URL { URL(fileURLWithPath: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(location)")
    }
}

struct MindMapQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MindMapEntity] {
        identifiers
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(MindMapCatalog.entity(for:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [MindMapEntity] {
        MindMapCatalog.search(string, in: MindMapCatalog.libraryDocuments()).map { MindMapCatalog.entity(for: $0.url) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MindMapEntity] {
        MindMapCatalog.libraryDocuments()
            .sorted { $0.modified > $1.modified }
            .prefix(40)
            .map { MindMapCatalog.entity(for: $0.url) }
    }
}

/// Exportformate für Kurzbefehle (TextBundle fehlt: ein Paket lässt sich nicht als einzelne Datei weitergeben).
enum ShortcutExportFormat: String, AppEnum, CaseIterable {
    case pdf, png, svg, markdown, opml, text, rtf, freeMind

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static let caseDisplayRepresentations: [ShortcutExportFormat: DisplayRepresentation] = [
        .pdf: "PDF",
        .png: "PNG-Bild",
        .svg: "SVG",
        .markdown: "Markdown",
        .opml: "OPML",
        .text: "Klartext",
        .rtf: "RTF",
        .freeMind: "FreeMind",
    ]

    var format: ExportFormat {
        switch self {
        case .pdf: return .pdf
        case .png: return .png
        case .svg: return .svg
        case .markdown: return .markdown
        case .opml: return .opml
        case .text: return .plainText
        case .rtf: return .rtf
        case .freeMind: return .freeMind
        }
    }
}

// MARK: - Aktionen

struct CreateMindMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Neue Mindmap"
    static let description = IntentDescription("Legt in der Bibliothek eine neue Mindmap an und öffnet sie.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Hauptthema", description: "Text des Hauptknotens und Name der Datei.", default: "Zentrales Thema")
    var topic: String

    static var parameterSummary: some ParameterSummary {
        Summary("Neue Mindmap „\(\.$topic)“")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MindMapEntity> {
        let text = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = ShortcutSupport.fileName(for: text.isEmpty ? L("Zentrales Thema") : text)
        let library = MindMapCatalog.libraryURL
        try LibraryStore.ensureLibrary(at: library)
        let data = MindMapDocumentData(root: Node(text: text.isEmpty ? L("Zentrales Thema") : text))
        let url = try LibraryStore.createDocument(data, named: name, in: library)
        MindMapCatalog.open(url)
        return .result(value: MindMapCatalog.entity(for: url))
    }
}

struct OpenMindMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Mindmap öffnen"
    static let description = IntentDescription("Öffnet eine Mindmap. Ohne Auswahl die zuletzt benutzte.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Mindmap", description: "Leer lassen für die zuletzt benutzte Mindmap.")
    var document: MindMapEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$document) öffnen")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        MindMapCatalog.open(try MindMapCatalog.resolve(document))
        return .result()
    }
}

struct LastMindMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Zuletzt benutzte Mindmap"
    static let description = IntentDescription("Liefert die zuletzt geöffnete Mindmap – zum Weiterreichen an andere Aktionen.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MindMapEntity> {
        .result(value: MindMapCatalog.entity(for: try MindMapCatalog.lastUsedURL()))
    }
}

struct FindMindMapsIntent: AppIntent {
    static let title: LocalizedStringResource = "Mindmaps suchen"
    static let description = IntentDescription("Sucht Mindmaps, deren Titel oder Knoten den Suchbegriff enthalten.")

    @Parameter(title: "Suchbegriff")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Mindmaps mit „\(\.$query)“ suchen")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[MindMapEntity]> & ProvidesDialog {
        let found = MindMapCatalog.search(query, in: MindMapCatalog.libraryDocuments())
        let entities = found.map { MindMapCatalog.entity(for: $0.url) }
        let dialog: IntentDialog
        switch entities.count {
        case 0: dialog = "Keine Mindmap enthält „\(query)“."
        case 1: dialog = "Gefunden: \(entities[0].title)."
        default: dialog = "\(entities.count) Mindmaps enthalten „\(query)“."
        }
        return .result(value: entities, dialog: dialog)
    }
}

struct ExportMindMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Mindmap exportieren"
    static let description = IntentDescription(
        "Exportiert eine Mindmap als PDF, Bild oder Text. Ohne Auswahl die zuletzt benutzte. Die Datei lässt sich mit „Datei sichern“ ablegen oder teilen.")

    @Parameter(title: "Mindmap", description: "Leer lassen für die zuletzt benutzte Mindmap.")
    var document: MindMapEntity?

    @Parameter(title: "Format", default: .pdf)
    var format: ShortcutExportFormat

    @Parameter(title: "PDF auf eine Seite", description: "Aus: A4-Seiten zum Drucken.", default: false)
    var singlePage: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$document) als \(\.$format) exportieren") {
            \.$singlePage
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let url = try MindMapCatalog.resolve(document)
        let file = try ShortcutSupport.export(url, format: format.format, singlePage: singlePage)
        return .result(value: file)
    }
}

struct AddNodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Knoten hinzufügen"
    static let description = IntentDescription(
        "Fügt einer Mindmap einen Knoten hinzu – unter dem Hauptknoten oder unter einem Knoten mit bestimmtem Text. Ohne Auswahl in der zuletzt benutzten Mindmap.")

    @Parameter(title: "Text")
    var text: String

    @Parameter(title: "Mindmap", description: "Leer lassen für die zuletzt benutzte Mindmap.")
    var document: MindMapEntity?

    @Parameter(title: "Unter Knoten", description: "Text des Knotens, unter den der neue kommt. Leer = Hauptknoten.")
    var parent: String?

    @Parameter(title: "Als Aufgabe", default: false)
    var asTask: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("„\(\.$text)“ zu \(\.$document) hinzufügen") {
            \.$parent
            \.$asTask
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let url = try MindMapCatalog.resolve(document)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try MindMapCatalog.modify(url, actionName: "Knoten hinzufügen (Kurzbefehl)") { data in
            _ = try MindMapPackage.addNode(trimmed, asTask: asTask, under: parent, to: &data)
        }
        return .result(dialog: "„\(trimmed)“ steht jetzt in „\(MindMapCatalog.title(of: url))“.")
    }
}

// MARK: - Siri und Spotlight-Vorschläge

struct MindMapsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ExportMindMapIntent(),
                    phrases: [
                        "Letzte Mindmap aus \(.applicationName) exportieren",
                        "Letzte Mindmap aus \(.applicationName) als \(\.$format) exportieren",
                    ],
                    shortTitle: "Mindmap exportieren",
                    systemImageName: "square.and.arrow.up")
        AppShortcut(intent: CreateMindMapIntent(),
                    phrases: [
                        "Neue Mindmap in \(.applicationName)",
                        "Erstelle eine Mindmap mit \(.applicationName)",
                    ],
                    shortTitle: "Neue Mindmap",
                    systemImageName: "plus.circle")
        AppShortcut(intent: AddNodeIntent(),
                    phrases: [
                        "Knoten in \(.applicationName) hinzufügen",
                        "Füge in \(.applicationName) einen Knoten hinzu",
                    ],
                    shortTitle: "Knoten hinzufügen",
                    systemImageName: "plus.bubble")
        AppShortcut(intent: FindMindMapsIntent(),
                    phrases: [
                        "Mindmaps in \(.applicationName) suchen",
                        "Suche in \(.applicationName)",
                    ],
                    shortTitle: "Mindmaps suchen",
                    systemImageName: "magnifyingglass")
        AppShortcut(intent: OpenMindMapIntent(),
                    phrases: [
                        "Letzte Mindmap in \(.applicationName) öffnen",
                    ],
                    shortTitle: "Mindmap öffnen",
                    systemImageName: "doc.richtext")
    }
}

// MARK: - Hilfen

@MainActor
enum ShortcutSupport {
    /// Dateiname aus einem Knotentext (ohne / und :, höchstens 80 Zeichen).
    static func fileName(for text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? L("Mindmap") : String(cleaned.prefix(80))
    }

    /// Exportiert ein Dokument wie der Export-Dialog.
    static func export(_ url: URL, format: ExportFormat, singlePage: Bool) throws -> IntentFile {
        let content = try MindMapCatalog.load(url)
        let title = MindMapCatalog.title(of: url)
        var options = ExportOptions()
        options.paging = singlePage ? .singlePage : .a4
        let wrapper = try MapImageExporter.fileWrapper(for: content.data, assets: content.assets, format: format,
                                                       options: options, title: title)
        guard let contents = wrapper.regularFileContents else { throw MapImageExporter.ExportError.renderFailed }
        return IntentFile(data: contents, filename: "\(title).\(format.fileExtension)", type: format.contentType)
    }
}
