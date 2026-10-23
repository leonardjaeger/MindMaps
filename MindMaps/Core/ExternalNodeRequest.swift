import Foundation

// MARK: - Knoten aus einem Link anlegen (1.3, M30 der PDF-App)

/// Bitte von außen (meist aus MintMarkPDF), einen Knoten anzulegen:
/// `mindmaps://add?v=1&file=<Pfad>&parent=<UUID>&title=<Text>&note=<Markdown>&link=<URL>`
///
/// - `file`: absoluter Pfad einer `.mindmaps`-Datei (Pflicht).
/// - `title`: Text des neuen Knotens (Pflicht, wird gesäubert und gekürzt).
/// - `parent`: Knoten, unter den der neue kommt – fehlt oder ungültig: der Hauptknoten.
/// - `note`: Notiz als Markdown (kommt fertig maskiert), `link`: Link am Knoten (nur erlaubte Schemata).
/// - `v`: Fassung des Formats; fehlt = 1, neuere Fassungen werden abgelehnt.
///
/// Der Leser ist bewusst streng: Was nicht passt, fällt weg oder der ganze Link wird abgelehnt.
/// Titel, Notiz, Link und Pfad sind privat und kommen nie ins Protokoll (Regel 14).
struct ExternalNodeRequest: Equatable {
    static let scheme = "mindmaps"
    static let host = "add"
    static let version = 1

    /// Höchstlänge des ganzen Links (Zeichen).
    static let maximumRequestLength = 16_000
    static let maximumPathLength = 4_096
    static let maximumTitleLength = 200
    static let maximumNoteLength = 2_000
    /// Höchstlänge eines Links am Knoten (aus `link=` oder per Ziehen).
    static let maximumLinkLength = 4_000
    /// Schemata, die ein Link von außen haben darf. `javascript:`, `file:` & Co. bleiben draußen.
    static let allowedLinkSchemes: Set<String> = ["mintmarkpdf", "http", "https", "mailto", "mindmaps"]
    /// Schema der Links auf eine Stelle in einem PDF (MintMarkPDF).
    static let passageScheme = "mintmarkpdf"

    let file: URL
    let parent: UUID?
    let title: String
    let note: String?
    let link: String?

    // MARK: Erkennen und Lesen

    /// Ist das ein Anlegen-Link (`mindmaps://add…`)? Schema und Ziel ohne Groß-/Kleinschreibung.
    /// Muss vor `DocumentLink.parse` geprüft werden – sonst sähe ein add-Link mit `file=` wie ein Öffnen-Link aus.
    static func isAddLink(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed) {
            return components.scheme?.lowercased() == scheme && components.host?.lowercased() == host
        }
        // Lässt sich der Link nicht zerlegen, entscheidet der Anfang (dann lehnt `parse` ihn ab).
        return trimmed.lowercased().hasPrefix("\(scheme)://\(host)?")
    }

    /// Liest einen Anlegen-Link. `nil`, wenn er ungültig, zu lang oder aus einer neueren Fassung ist.
    static func parse(_ string: String) -> ExternalNodeRequest? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumRequestLength,
              let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host else { return nil }

        // Werte (schon prozentdekodiert); bei doppelten Namen gilt der erste, Unbekanntes wird übergangen.
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] where values[item.name] == nil {
            if let value = item.value { values[item.name] = value }
        }

        if let v = values["v"] {
            guard let number = Int(v), number >= 1, number <= version else { return nil }
        }

        guard let path = values["file"], path.hasPrefix("/"), path.count <= maximumPathLength,
              !path.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        let file = URL(fileURLWithPath: path)
        guard file.pathExtension.lowercased() == "mindmaps" else { return nil }

        let title = shortened(cleanedTitle(values["title"] ?? ""), to: maximumTitleLength)
        guard !title.isEmpty else { return nil }

        let note = values["note"].map { shortened(cleanedNote($0), to: maximumNoteLength) }
        return ExternalNodeRequest(file: file,
                                   parent: values["parent"].flatMap(UUID.init(uuidString:)),
                                   title: title,
                                   note: (note?.isEmpty ?? true) ? nil : note,
                                   link: values["link"].flatMap(acceptedLink))
    }

    // MARK: Links

    /// Prüft einen Link für einen Knoten (aus `link=` oder per Ziehen auf einen Knoten):
    /// getrimmt, eine Zeile ohne Leerzeichen, höchstens 4.000 Zeichen, Schema mintmarkpdf, http(s),
    /// mailto oder mindmaps. Anlegen-Links werden nie als Link übernommen – ein Klick darauf würde sonst
    /// einen Knoten anlegen. `nil` = nicht annehmen.
    static func acceptedLink(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumLinkLength,
              !trimmed.unicodeScalars.contains(where: { scalar in
                  CharacterSet.whitespacesAndNewlines.contains(scalar)
                      || scalar.properties.generalCategory == .control
                      || scalar.properties.generalCategory == .format
              }),
              let colon = trimmed.firstIndex(of: ":") else { return nil }
        let linkScheme = trimmed[..<colon].lowercased()
        guard allowedLinkSchemes.contains(linkScheme) else { return nil }
        let rest = trimmed[trimmed.index(after: colon)...]
        if linkScheme == "mailto" {
            guard !rest.isEmpty else { return nil }
        } else {
            // „https://“ allein ist kein Link.
            guard rest.hasPrefix("//"), rest.count > 2 else { return nil }
        }
        guard !isAddLink(trimmed) else { return nil }
        return trimmed
    }

    /// Link auf eine Stelle in einem PDF (`mintmarkpdf://…`)? Für den Anzeigenamen im Knoten-Inspektor.
    static func isPassageLink(_ link: String) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.firstIndex(of: ":") else { return false }
        return trimmed[..<colon].lowercased() == passageScheme
    }

    // MARK: Säubern und Kürzen

    /// Titel: Zeilenumbrüche und Tabs werden Leerzeichen, Steuer- und Formatzeichen fallen weg
    /// (außer dem Verbinder U+200D in Emojis), mehrere Leerzeichen werden eins.
    static func cleanedTitle(_ text: String) -> String {
        collapsedSpaces(withoutInvisibles(text, keepLineBreaks: false))
    }

    /// Notiz: wie der Titel, aber Zeilenumbrüche bleiben (jede Zeile für sich gesäubert).
    static func cleanedNote(_ text: String) -> String {
        withoutInvisibles(text, keepLineBreaks: true)
            .components(separatedBy: "\n")
            .map(collapsedSpaces)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Kürzt auf höchstens `limit` Zeichen; gekürzte Texte enden mit „…“.
    static func shortened(_ text: String, to limit: Int) -> String {
        guard limit > 1, text.count > limit else { return text }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Zeilenumbrüche werden „\n“ (mit `keepLineBreaks`) oder Leerzeichen, Tabs Leerzeichen;
    /// übrige Steuer- und Formatzeichen (Unicode Cc/Cf) fallen weg – außer U+200D.
    private static func withoutInvisibles(_ text: String, keepLineBreaks: Bool) -> String {
        let breaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}"]
        var result = String.UnicodeScalarView()
        var previous: Unicode.Scalar?
        for scalar in text.unicodeScalars {
            defer { previous = scalar }
            if breaks.contains(scalar) {
                // „\r\n“ ist ein Umbruch, nicht zwei.
                if scalar == "\n", previous == "\r" { continue }
                result.append(keepLineBreaks ? "\n" : " ")
            } else if scalar == "\t" {
                result.append(" ")
            } else if scalar == "\u{200D}" {
                result.append(scalar)
            } else {
                let category = scalar.properties.generalCategory
                if category != .control && category != .format { result.append(scalar) }
            }
        }
        return String(result)
    }

    /// Mehrere Leerzeichen (auch geschützte) werden eins, außen getrimmt.
    private static func collapsedSpaces(_ line: String) -> String {
        line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Anlegen im Dokument (ohne Oberfläche)

extension ExternalNodeRequest {
    /// Wo der Knoten gelandet ist.
    struct Placement: Equatable {
        let nodeID: UUID
        /// `parent` war angegeben, gibt es aber nicht (mehr) – der Knoten hängt am Hauptknoten.
        let parentMissing: Bool
    }

    /// Hängt den Knoten mit Titel, Notiz und Link an `parent` (sonst an den Hauptknoten) und klappt
    /// den Weg dorthin auf. Der Aufrufer bündelt das in einen Rückgängig-Schritt.
    func insert(into data: inout MindMapDocumentData) -> Placement {
        let root = data.root
        let parentExists = parent.map { root.contains($0) } ?? false
        let parentID = parentExists ? (parent ?? root.id) : root.id
        let node = Node(text: title, note: note ?? "", link: link ?? "")
        data.root.addChild(node, to: parentID)
        data.root.expandAncestors(of: node.id)
        return Placement(nodeID: node.id, parentMissing: parent != nil && !parentExists)
    }
}
