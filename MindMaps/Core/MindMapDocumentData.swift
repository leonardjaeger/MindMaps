import Foundation

/// Inhalt einer `.mindmaps`-Datei (wird als `document.json` im Dateipaket gespeichert).
struct MindMapDocumentData: Codable, Equatable {
    static let currentFormatVersion = 1
    static let defaultThemeID = "blau"

    var formatVersion: Int
    var root: Node
    var themeID: String
    var createdAt: Date
    var modifiedAt: Date
    /// Querverbindungen zwischen beliebigen Knoten (seit M7).
    var connections: [Connection] = []
    /// Layout und Zweige (seit M8).
    var style = MapStyle()
    /// Eigenes Thema, im Dokument mitgespeichert – so sieht die Map auch auf einem anderen Mac gleich aus (seit M8).
    var customTheme: Theme?
    /// Aufgaben mit einer Liste in Erinnerungen abgleichen (seit M9; `nil` = aus).
    var reminders: RemindersLink?

    init(root: Node,
         themeID: String = MindMapDocumentData.defaultThemeID,
         createdAt: Date = MindMapDocumentData.now(),
         modifiedAt: Date = MindMapDocumentData.now()) {
        self.formatVersion = Self.currentFormatVersion
        self.root = root
        self.themeID = themeID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Neues Dokument mit einem Hauptknoten.
    static func newDocument() -> MindMapDocumentData {
        MindMapDocumentData(root: Node(text: L("Zentrales Thema")))
    }

    /// Aktuelle Zeit auf ganze Sekunden gerundet (so übersteht sie den ISO-8601-Export unverändert).
    static func now() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, root, themeID, createdAt, modifiedAt, connections, style, customTheme, reminders
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(root, forKey: .root)
        try c.encode(themeID, forKey: .themeID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        if !connections.isEmpty { try c.encode(connections, forKey: .connections) }
        if !style.isDefault { try c.encode(style, forKey: .style) }
        if let customTheme { try c.encode(customTheme, forKey: .customTheme) }
        if let reminders { try c.encode(reminders, forKey: .reminders) }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        root = try c.decode(Node.self, forKey: .root)
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? Self.defaultThemeID
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.now()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        connections = (try? c.decodeIfPresent([Connection].self, forKey: .connections)) ?? []
        style = (try? c.decodeIfPresent(MapStyle.self, forKey: .style)) ?? MapStyle()
        customTheme = try? c.decodeIfPresent(Theme.self, forKey: .customTheme)
        reminders = try? c.decodeIfPresent(RemindersLink.self, forKey: .reminders)
    }
}

/// Wandelt Dokumente in JSON um und zurück.
enum MindMapCodec {
    enum CodecError: Error, Equatable, LocalizedError {
        case unsupportedFormatVersion(Int)
        case missingDocumentJSON

        var errorDescription: String? {
            switch self {
            case .unsupportedFormatVersion(let v):
                return L("Diese Datei wurde mit einer neueren Version von MindMaps erstellt (Format %@).", "\(v)")
            case .missingDocumentJSON:
                return L("Die Datei ist beschädigt: document.json fehlt.")
            }
        }
    }

    static let documentFileName = "document.json"
    static let assetsFolderName = "assets"

    static func encode(_ document: MindMapDocumentData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> MindMapDocumentData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(MindMapDocumentData.self, from: data)
        guard document.formatVersion <= MindMapDocumentData.currentFormatVersion else {
            throw CodecError.unsupportedFormatVersion(document.formatVersion)
        }
        return document
    }
}
