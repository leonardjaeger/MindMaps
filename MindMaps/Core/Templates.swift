import Foundation

/// Vorlagen für neue Dokumente (Bibliothek › Neu).
enum DocumentTemplate: String, CaseIterable, Identifiable {
    case blank, referat, lernzettel, projektplan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blank: return L("Leer")
        case .referat: return L("Referat")
        case .lernzettel: return L("Lernzettel")
        case .projektplan: return L("Projektplan")
        }
    }

    var symbol: String {
        switch self {
        case .blank: return "doc"
        case .referat: return "person.wave.2"
        case .lernzettel: return "book.closed"
        case .projektplan: return "checklist"
        }
    }

    /// Dateiname eines neuen Dokuments aus dieser Vorlage.
    var fileName: String {
        self == .blank ? L("Unbenannt") : title
    }

    func makeDocument() -> MindMapDocumentData {
        switch self {
        case .blank:
            return .newDocument()
        case .referat:
            return Self.build(L("Thema des Referats"), theme: "blau", [
                (L("Einleitung"), [L("Einstieg"), L("Ziel"), L("Gliederung")]),
                (L("Hauptteil"), [L("Punkt 1"), L("Punkt 2"), L("Punkt 3")]),
                (L("Schluss"), [L("Zusammenfassung"), L("Fazit"), L("Fragen an die Zuhörer")]),
                (L("Quellen"), [L("Literatur"), L("Internet")])
            ])
        case .lernzettel:
            return Self.build(L("Fach / Thema"), theme: "pastell", [
                (L("Grundbegriffe"), [L("Begriff 1"), L("Begriff 2"), L("Begriff 3")]),
                (L("Zusammenhänge"), [L("Ursache"), L("Wirkung")]),
                (L("Beispiele"), [L("Beispiel 1"), L("Beispiel 2")]),
                (L("Merksätze"), [L("Merksatz")]),
                (L("Offene Fragen"), [])
            ])
        case .projektplan:
            return Self.build(L("Projekt"), theme: "ozean", [
                (L("Ziel"), [L("Ergebnis"), L("Termin")]),
                (L("Aufgaben"), [L("Aufgabe 1"), L("Aufgabe 2"), L("Aufgabe 3")]),
                (L("Beteiligte"), [L("Person 1"), L("Person 2")]),
                (L("Zeitplan"), [L("Start"), L("Zwischenstand"), L("Abgabe")]),
                (L("Risiken"), [])
            ])
        }
    }

    /// Baut ein Dokument aus Hauptknoten, Ästen und deren Unterknoten.
    static func build(_ rootText: String, theme: String,
                      _ branches: [(String, [String])]) -> MindMapDocumentData {
        let children = branches.map { branch, leaves in
            Node(text: branch, children: leaves.map { Node(text: $0) })
        }
        return MindMapDocumentData(root: Node(text: rootText, children: children), themeID: theme)
    }
}
