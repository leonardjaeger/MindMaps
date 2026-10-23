import Foundation

/// Beispieldokumente: 20 Mindmaps in verschachtelten Ordnern (für die Abnahme von M4 und zum Ausprobieren).
enum SampleLibrary {
    /// Ordnerpfad (relativ, mit "/") → Dokumente darin.
    static let structure: [(folder: String, documents: [(name: String, data: MindMapDocumentData)])] = [
        ("Studium/Pädagogik/Referate", [
            ("Referat Lerntheorien", referat("Lerntheorien", ["Behaviorismus", "Kognitivismus", "Konstruktivismus"])),
            ("Referat Heterogenität", referat("Heterogenität", ["Leistung", "Sprache", "Herkunft"])),
            ("Referat Motivation", referat("Motivation", ["Intrinsisch", "Extrinsisch", "Selbstbestimmung"]))
        ]),
        ("Studium/Pädagogik", [
            ("Lernzettel Entwicklungspsychologie", lernzettel("Entwicklungspsychologie", ["Piaget", "Wygotski", "Erikson"])),
            ("Lernzettel Didaktik", lernzettel("Didaktik", ["Ziele", "Inhalte", "Methoden"]))
        ]),
        ("Studium/Biologie", [
            ("Lernzettel Zelle", lernzettel("Zelle", ["Zellkern", "Mitochondrien", "Zellmembran"])),
            ("Lernzettel Photosynthese", photosynthese()),
            ("Referat Ökosysteme", referat("Ökosysteme", ["Wald", "See", "Wiese"])),
            ("Referat Wasserkreislauf", referat("Wasserkreislauf", ["Verdunstung", "Kondensation", "Niederschlag"]))
        ]),
        ("Studium/Mathematik", [
            ("Lernzettel Bruchrechnung", lernzettel("Bruchrechnung", ["Erweitern", "Kürzen", "Addieren"])),
            ("Lernzettel Geometrie", lernzettel("Geometrie", ["Dreieck", "Kreis", "Vierecke"]))
        ]),
        ("Projekte/Hausarbeit", [
            ("Projektplan Hausarbeit", projekt("Hausarbeit", ["Thema finden", "Literatur", "Schreiben"])),
            ("Gliederung Hausarbeit", referat("Hausarbeit", ["Theorie", "Methode", "Ergebnisse"]))
        ]),
        ("Projekte", [
            ("Projektplan Praktikum", projekt("Praktikum", ["Bewerbung", "Hospitation", "Bericht"]))
        ]),
        ("Privat", [
            ("Urlaub planen", simple("Urlaub", ["Ziel", "Anreise", "Packliste", "Budget"])),
            ("Umzug", simple("Umzug", ["Kartons", "Ummelden", "Helfer", "Termine"])),
            ("Geschenkideen", simple("Geschenkideen", ["Geburtstage", "Weihnachten", "Kleinigkeiten"]))
        ]),
        ("", [
            ("Ideen", simple("Ideen", ["Studium", "Freizeit", "Irgendwann"])),
            ("Wochenplan", simple("Woche", ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"])),
            ("Bücherliste", simple("Bücher", ["Gelesen", "Als Nächstes", "Empfehlungen"]))
        ])
    ]

    static var documentCount: Int { structure.reduce(0) { $0 + $1.documents.count } }

    /// Legt alle Beispiele im Ordner „Beispiele“ der Bibliothek an und liefert diesen Ordner.
    @discardableResult
    static func create(in root: URL) throws -> URL {
        let base = try LibraryStore.createFolder(named: "Beispiele", in: root)
        for (folder, documents) in structure {
            let target = folder.isEmpty ? base : base.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for (name, data) in documents {
                try LibraryStore.createDocument(data, named: name, in: target)
            }
        }
        return base
    }

    // MARK: - Inhalte

    private static func referat(_ topic: String, _ points: [String]) -> MindMapDocumentData {
        DocumentTemplate.build("Referat: \(topic)", theme: "blau", [
            ("Einleitung", ["Einstieg", "Ziel"]),
            ("Hauptteil", points),
            ("Schluss", ["Zusammenfassung", "Fragen"])
        ])
    }

    private static func lernzettel(_ topic: String, _ terms: [String]) -> MindMapDocumentData {
        DocumentTemplate.build(topic, theme: "pastell", [
            ("Grundbegriffe", terms),
            ("Beispiele", ["Beispiel 1"]),
            ("Merksätze", ["Merksatz"])
        ])
    }

    private static func projekt(_ name: String, _ tasks: [String]) -> MindMapDocumentData {
        DocumentTemplate.build(name, theme: "ozean", [
            ("Ziel", ["Ergebnis", "Termin"]),
            ("Aufgaben", tasks),
            ("Zeitplan", ["Start", "Abgabe"])
        ])
    }

    private static func simple(_ root: String, _ branches: [String]) -> MindMapDocumentData {
        DocumentTemplate.build(root, theme: "schwarzwald", branches.map { ($0, []) })
    }

    /// Enthält „Chlorophyll“ tief im Baum (4. Ebene) – zum Testen der Suche.
    private static func photosynthese() -> MindMapDocumentData {
        var data = lernzettel("Photosynthese", ["Licht", "Wasser", "Kohlendioxid"])
        let licht = data.root.children[0].children[0]
        data.root.updateNode(id: licht.id) { node in
            node.children = [Node(text: "Chlorophyll fängt das Licht ein")]
        }
        return data
    }
}
