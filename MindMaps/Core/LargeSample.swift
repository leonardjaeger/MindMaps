import Foundation

/// Große Beispiel-Mindmap für Leistungstests (M12): 1.000 Knoten mit Aufgaben, Tags, Notizen,
/// Links und Formeln – so, wie eine lange Prüfungsvorbereitung aussehen könnte. Immer gleich aufgebaut.
enum LargeSample {
    private static let subjects = ["Biologie", "Chemie", "Geschichte", "Mathematik",
                                   "Pädagogik", "Psychologie", "Deutsch", "Informatik"]
    private static let topics = ["Grundbegriffe", "Modelle", "Methoden", "Beispiele", "Übungen",
                                 "Klausurfragen", "Literatur", "Zusammenfassung", "Vertiefung", "Anwendung"]
    private static let words = ["Definition", "Ursache", "Wirkung", "Merkmal", "Vergleich", "Kritik",
                                "Experiment", "Beobachtung", "These", "Gegenargument", "Fallbeispiel", "Formel"]

    static func document(nodeCount: Int = 1000) -> MindMapDocumentData {
        var remaining = max(nodeCount - 1, 0)
        var counter = 0
        var generator = Numbers(seed: 20260926)

        func text(depth: Int, index: Int) -> String {
            switch depth {
            case 1: return subjects[index % subjects.count]
            case 2: return topics[index % topics.count]
            default:
                let word = words[generator.next(words.count)]
                if generator.next(5) == 0 {
                    return "\(word) \(counter): ausführlicher erklärt, damit der Knoten über mehrere Zeilen umbricht"
                }
                return "\(word) \(counter)"
            }
        }

        func make(depth: Int, index: Int) -> Node {
            counter += 1
            var node = Node(id: generator.uuid(), text: text(depth: depth, index: index))
            if depth >= 3 {
                if counter % 6 == 0 { node.task = counter % 12 == 0 ? .done : .open }
                if counter % 9 == 0 { node.tags = [["Wichtig", "Prüfung", "Merken"][counter % 3]] }
                if counter % 7 == 0 { node.note = "Notiz zu **\(node.text)** – mit Stichpunkten:\n- erstens\n- zweitens" }
                if counter % 97 == 0 { node.formula = "a^2 + b^2 = c^2" }
                if counter % 53 == 0 { node.link = "https://de.wikipedia.org/wiki/Mindmap" }
            }
            let fan = depth == 0 ? subjects.count : depth == 1 ? 6 : depth == 2 ? 5 : 3
            if depth < 4 {
                for i in 0..<fan where remaining > 0 {
                    remaining -= 1
                    node.children.append(make(depth: depth + 1, index: i))
                }
            }
            return node
        }

        var root = make(depth: 0, index: 0)
        root.text = "Leistungstest: \(nodeCount) Knoten"
        // Reicht die feste Verzweigung nicht, kommen weitere Knoten unter die Fächer.
        var extra = 0
        while remaining > 0 {
            let branch = extra % root.children.count
            root.children[branch].children.append(Node(id: generator.uuid(), text: "Ergänzung \(extra + 1)"))
            remaining -= 1
            extra += 1
        }
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        return MindMapDocumentData(root: root, createdAt: created, modifiedAt: created)
    }

    /// Einfacher Zufallsgenerator mit festem Startwert – liefert jedes Mal dieselbe Map.
    private struct Numbers {
        var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func nextRaw() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func next(_ bound: Int) -> Int { Int((nextRaw() >> 33) % UInt64(bound)) }

        mutating func uuid() -> UUID {
            let a = nextRaw(), b = nextRaw()
            var bytes = [UInt8](repeating: 0, count: 16)
            for i in 0..<8 {
                bytes[i] = UInt8((a >> (8 * UInt64(i))) & 0xff)
                bytes[8 + i] = UInt8((b >> (8 * UInt64(i))) & 0xff)
            }
            bytes[6] = (bytes[6] & 0x0f) | 0x40
            bytes[8] = (bytes[8] & 0x3f) | 0x80
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        }
    }
}
