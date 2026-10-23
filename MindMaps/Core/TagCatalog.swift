import Foundation

/// Ein Tag mit Farbe. Die Farben gelten für alle Dokumente (Tag-Katalog der App).
struct TagDefinition: Codable, Equatable, Identifiable {
    var name: String
    /// Index in `TagCatalog.colors`.
    var color: Int

    var id: String { name }
}

/// Die Tags der App. In den Dokumenten stehen nur die Namen; ein unbekanntes Tag
/// (z. B. aus einem fremden Dokument) bekommt eine feste, aus dem Namen berechnete Farbe.
struct TagCatalog: Codable, Equatable {
    var tags: [TagDefinition]

    /// Farben mit gutem Kontrast auf hellem und dunklem Grund.
    static let colors: [(name: String, hex: String)] = [
        (L("Rot"), "#E5484D"), (L("Orange"), "#F76B15"), (L("Gelb"), "#E2A300"), (L("Grün"), "#30A46C"),
        (L("Blau"), "#0090FF"), (L("Lila"), "#8E4EC6"), (L("Pink"), "#D6409F"), (L("Türkis"), "#12A594"),
        (L("Grau"), "#8B8D98"),
    ]

    /// Vorgaben für das Lernen – mit Bedeutung, die das Tutorial erklärt.
    static let standard = TagCatalog(tags: [
        TagDefinition(name: L("Wichtig"), color: 0),
        TagDefinition(name: L("Prüfung"), color: 1),
        TagDefinition(name: L("Merken"), color: 2),
        TagDefinition(name: L("Beispiel"), color: 3),
        TagDefinition(name: L("Definition"), color: 4),
        TagDefinition(name: L("Frage"), color: 5),
        TagDefinition(name: L("Unklar"), color: 6),
    ])

    func definition(named name: String) -> TagDefinition? {
        tags.first { $0.name == name }
    }

    func colorIndex(for name: String) -> Int {
        if let known = definition(named: name) { return known.color }
        // FNV-1a: stabil über Programmstarts hinweg (anders als `hashValue`).
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(Self.colors.count))
    }

    func hex(for name: String) -> String {
        Self.colors[colorIndex(for: name) % Self.colors.count].hex
    }

    /// Katalog-Tags zuerst (in ihrer Reihenfolge), dann weitere Tags aus dem Dokument alphabetisch.
    func ordered(including extra: some Sequence<String>) -> [String] {
        let known = tags.map(\.name)
        let others = Set(extra).subtracting(known).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return known + others
    }

    /// Neuer Name nur, wenn er nicht leer ist und noch nicht existiert.
    mutating func add(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, definition(named: trimmed) == nil else { return false }
        tags.append(TagDefinition(name: trimmed, color: colorIndex(for: trimmed)))
        return true
    }
}
