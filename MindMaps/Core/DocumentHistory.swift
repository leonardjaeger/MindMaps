import Foundation

/// Ein Zwischenstand im Verlauf eines Dokuments (M10).
struct HistoryEntry: Codable, Equatable, Identifiable {
    /// Dateiname im Ordner `Verlauf/` des Pakets.
    var file: String
    var date: Date
    var nodeCount: Int
    /// Fingerabdruck des Inhalts – gleicher Inhalt wird nicht doppelt gesichert.
    var fingerprint: String
    /// Bilder, auf die der Zwischenstand verweist – sie bleiben im Paket, solange es ihn gibt.
    var assets: [String]

    var id: String { file }
}

/// Dokumentverlauf (M10): Zwischenstände im Paket, ausgedünnt nach Alter, und Wiederherstellen
/// einer ganzen Fassung oder eines einzelnen Zweigs. Nur Foundation, damit alles getestet werden kann.
///
/// Regeln:
/// - Beim Sichern entsteht ein Zwischenstand, wenn sich der Inhalt geändert hat und der letzte
///   mindestens 10 Minuten alt ist.
/// - Aufbewahrt wird: aus den letzten 24 Stunden einer je 10 Minuten, aus den letzten 30 Tagen einer
///   pro Tag, davor einer pro Woche – jeweils der neueste. Höchstens 300 insgesamt.
enum DocumentHistory {
    static let folderName = "Verlauf"
    static let indexFileName = "index.json"
    static let minimumInterval: TimeInterval = 10 * 60
    static let maximumEntries = 300

    // MARK: - Fingerabdruck

    /// Fingerabdruck des Inhalts (ohne Änderungsdatum), FNV-1a über das JSON.
    static func fingerprint(of document: MindMapDocumentData) -> String {
        var normalized = document
        normalized.modifiedAt = Date(timeIntervalSince1970: 0)
        let json = (try? MindMapCodec.encode(normalized)) ?? Data()
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in json {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Aufnehmen und ausdünnen

    /// Soll jetzt ein Zwischenstand entstehen?
    static func shouldRecord(fingerprint: String, at date: Date, after entries: [HistoryEntry]) -> Bool {
        guard let last = entries.max(by: { $0.date < $1.date }) else { return true }
        return last.fingerprint != fingerprint && date.timeIntervalSince(last.date) >= minimumInterval
    }

    /// Dateiname für einen Zeitpunkt, z. B. „20260926-143000“ (UTC, sortiert sich zeitlich).
    static func baseName(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        return "\(c.year ?? 0)\(two(c.month))\(two(c.day))-\(two(c.hour))\(two(c.minute))\(two(c.second))"
    }

    /// Welche Zwischenstände bleiben (neueste zuerst)?
    static func thinned(_ entries: [HistoryEntry], now: Date, calendar: Calendar = .current) -> [HistoryEntry] {
        var seen = Set<String>()
        var kept: [HistoryEntry] = []
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            let age = now.timeIntervalSince(entry.date)
            let bucket: String
            if age < 24 * 3600 {
                bucket = "m\(Int((entry.date.timeIntervalSince1970 / minimumInterval).rounded(.down)))"
            } else if age < 30 * 24 * 3600 {
                let day = calendar.dateComponents([.year, .month, .day], from: entry.date)
                bucket = "d\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
            } else {
                let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: entry.date)
                bucket = "w\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)"
            }
            if seen.insert(bucket).inserted { kept.append(entry) }
        }
        return Array(kept.prefix(maximumEntries))
    }

    static func encodeIndex(_ entries: [HistoryEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(entries.sorted { $0.date > $1.date })
    }

    static func decodeIndex(_ data: Data) -> [HistoryEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    // MARK: - Wiederherstellen

    /// Holt eine ganze Fassung zurück. Der Abgleich mit Erinnerungen und das Erstellungsdatum bleiben.
    static func restoreAll(from old: MindMapDocumentData, into current: inout MindMapDocumentData) {
        var restored = old
        restored.reminders = current.reminders
        restored.createdAt = current.createdAt
        restored.modifiedAt = current.modifiedAt
        current = restored
    }

    /// Holt einen Zweig aus einer alten Fassung zurück, der Rest der Map bleibt, wie er ist.
    ///
    /// - Gibt es den Knoten noch, ersetzt der alte Stand seinen Teilbaum.
    /// - Ist er gelöscht, kommt er unter seinen alten Elternknoten (bzw. den nächsten Vorfahren,
    ///   den es noch gibt) – an seine alte Stelle zwischen den Geschwistern.
    /// - Knoten, die inzwischen anderswo in der Map stehen, kommen als Kopie mit neuer ID zurück.
    /// - Querverbindungen aus der alten Fassung kommen mit, wenn beide Enden wieder da sind.
    ///
    /// Liefert die ID des wiederhergestellten Zweigs in der aktuellen Map.
    @discardableResult
    static func restoreBranch(_ id: UUID, from old: MindMapDocumentData, into current: inout MindMapDocumentData,
                              newID: () -> UUID = { UUID() }) -> UUID? {
        guard var branch = old.root.node(withID: id) else { return nil }
        if id == old.root.id {
            restoreAll(from: old, into: &current)
            return current.root.id
        }
        let replacing = current.root.node(withID: id)
        let taken = current.root.subtreeIDs.subtracting(replacing?.subtreeIDs ?? [])
        var mapping: [UUID: UUID] = [:]
        branch.renumber(taken: taken, mapping: &mapping, newID: newID)

        if replacing != nil {
            current.root.updateNode(id: id) { $0 = branch }
        } else {
            let path = old.root.path(to: id) ?? []
            let ancestors = path.dropLast().reversed()
            let parentID = ancestors.first { current.root.contains($0) } ?? current.root.id
            var index: Int?
            if let oldParent = path.dropLast().last, oldParent == parentID,
               let oldSiblings = old.root.node(withID: oldParent)?.children.map(\.id),
               let oldIndex = oldSiblings.firstIndex(of: id),
               let currentSiblings = current.root.node(withID: parentID)?.children.map(\.id) {
                // Hinter das letzte Geschwister, das vorher davor stand und noch da ist.
                let before = oldSiblings[..<oldIndex].filter { currentSiblings.contains($0) }
                index = before.last.flatMap { currentSiblings.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            }
            current.root.addChild(branch, to: parentID, at: index)
            current.root.expandAncestors(of: branch.id)
        }

        // Querverbindungen, die in der alten Fassung am Zweig hingen.
        let restored = branch.subtreeIDs
        let existing = current.root.subtreeIDs
        var connectionIDs = Set(current.connections.map(\.id))
        for connection in old.connections {
            let from = mapping[connection.from] ?? connection.from
            let to = mapping[connection.to] ?? connection.to
            guard restored.contains(from) || restored.contains(to),
                  existing.contains(from), existing.contains(to),
                  !current.connections.contains(where: { $0.from == from && $0.to == to }) else { continue }
            var copy = connection
            copy.from = from
            copy.to = to
            if connectionIDs.contains(copy.id) { copy.id = newID() }
            connectionIDs.insert(copy.id)
            current.connections.append(copy)
        }
        current.pruneConnections()
        return branch.id
    }

    /// Knoten der alten Fassung, die es in der aktuellen Map nicht mehr gibt.
    static func removedSince(_ old: Node, current: Node) -> Set<UUID> {
        old.subtreeIDs.subtracting(current.subtreeIDs)
    }
}

extension Node {
    /// Vergibt neue IDs für alle Knoten, deren ID schon vergeben ist.
    fileprivate mutating func renumber(taken: Set<UUID>, mapping: inout [UUID: UUID], newID: () -> UUID) {
        if taken.contains(id) {
            let fresh = newID()
            mapping[id] = fresh
            id = fresh
        }
        for index in children.indices {
            children[index].renumber(taken: taken, mapping: &mapping, newID: newID)
        }
    }
}
