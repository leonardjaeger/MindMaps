import Foundation

/// Fortschritt einer Aufgabe bzw. eines Zweigs mit Aufgaben.
enum TaskStatus: Equatable {
    case open, partial, done

    var title: String {
        switch self {
        case .open: return "offen"
        case .partial: return "teilweise"
        case .done: return "erledigt"
        }
    }
}

/// Aufgaben, Tags, Notizen, Suchen & Ersetzen (M6).
extension Node {

    // MARK: - Aufgaben

    /// Erledigte und alle Aufgaben unterhalb dieses Knotens (ohne ihn selbst).
    /// Gezählt werden die „Blätter“ unter den Aufgaben: Eine Aufgabe mit eigenen Unteraufgaben
    /// zählt über ihre Unteraufgaben, nicht doppelt.
    var taskProgress: (done: Int, total: Int) {
        var done = 0, total = 0
        for child in children {
            let sub = child.taskProgress
            if sub.total > 0 {
                done += sub.done
                total += sub.total
            } else if let mark = child.task {
                total += 1
                if mark == .done { done += 1 }
            }
        }
        return (done, total)
    }

    /// Hat Unteraufgaben (irgendwo darunter)?
    var hasTaskDescendants: Bool { taskProgress.total > 0 }

    /// Zustand für Anzeige und Übersicht. Mit Unteraufgaben ergibt er sich aus ihnen,
    /// sonst aus der eigenen Markierung. `nil` = weder Aufgabe noch Aufgaben darunter.
    var taskStatus: TaskStatus? {
        let progress = taskProgress
        if progress.total > 0 {
            if progress.done == 0 { return .open }
            return progress.done == progress.total ? .done : .partial
        }
        switch task {
        case .open?: return .open
        case .done?: return .done
        case nil: return nil
        }
    }

    /// Setzt diesen Knoten und alle Aufgaben darunter auf erledigt bzw. offen.
    mutating func setTaskDone(_ done: Bool) {
        let mark: TaskMark = done ? .done : .open
        if task != nil || children.isEmpty || !hasTaskDescendants { task = mark }
        for i in children.indices where children[i].task != nil || children[i].hasTaskDescendants {
            children[i].setTaskDone(done)
        }
    }

    /// Aufgabe an/aus (⇧ ⌘ T).
    @discardableResult
    mutating func toggleTask(_ id: UUID) -> Bool {
        updateNode(id: id) { node in node.task = node.task == nil ? .open : nil }
    }

    /// Abhaken bzw. wieder öffnen (⇧ ⌘ D, Klick auf das Kästchen).
    /// Ein Knoten, der noch keine Aufgabe ist, wird dabei zur erledigten Aufgabe.
    @discardableResult
    mutating func toggleDone(_ id: UUID) -> Bool {
        updateNode(id: id) { node in
            node.setTaskDone(node.taskStatus != .done)
        }
    }

    /// Offene Aufgaben (auch teilweise erledigte) in Lesereihenfolge, mit dem Weg dorthin.
    func openTasks() -> [TaskEntry] {
        var result: [TaskEntry] = []
        func visit(_ node: Node, _ path: [String]) {
            if node.task != nil, let status = node.taskStatus, status != .done {
                result.append(TaskEntry(id: node.id, text: node.text, path: path, status: status))
            }
            for child in node.children { visit(child, path + [node.text]) }
        }
        visit(self, [])
        return result
    }

    // MARK: - Tags

    /// Alle vorkommenden Tags mit Anzahl der Knoten.
    var tagCounts: [String: Int] {
        var counts: [String: Int] = [:]
        func visit(_ node: Node) {
            for tag in Set(node.tags) { counts[tag, default: 0] += 1 }
            node.children.forEach(visit)
        }
        visit(self)
        return counts
    }

    /// Setzt oder entfernt ein Tag.
    @discardableResult
    mutating func toggleTag(_ tag: String, on id: UUID) -> Bool {
        updateNode(id: id) { node in
            if let index = node.tags.firstIndex(of: tag) {
                node.tags.remove(at: index)
            } else {
                node.tags.append(tag)
            }
        }
    }

    /// Benennt ein Tag in allen Knoten um (bzw. entfernt es bei `nil`).
    mutating func renameTag(_ old: String, to new: String?) {
        if let index = tags.firstIndex(of: old) {
            if let new, !tags.contains(new) { tags[index] = new } else { tags.remove(at: index) }
        }
        for i in children.indices { children[i].renameTag(old, to: new) }
    }

    /// IDs aller Knoten, auf die eine Bedingung zutrifft.
    func ids(where predicate: (Node) -> Bool) -> Set<UUID> {
        var result = Set<UUID>()
        func visit(_ node: Node) {
            if predicate(node) { result.insert(node.id) }
            node.children.forEach(visit)
        }
        visit(self)
        return result
    }

    // MARK: - Suchen und Ersetzen

    /// Treffer in Lesereihenfolge. Ein Knoten kommt höchstens einmal vor.
    func findMatches(_ query: String, options: FindOptions) -> [FindMatch] {
        guard !query.isEmpty else { return [] }
        var result: [FindMatch] = []
        func visit(_ node: Node) {
            let inText = node.text.range(of: query, options: options.compareOptions) != nil
            let inNote = options.includeNotes && node.note.range(of: query, options: options.compareOptions) != nil
            if inText || inNote { result.append(FindMatch(id: node.id, inText: inText, inNote: inNote)) }
            node.children.forEach(visit)
        }
        visit(self)
        return result
    }

    /// Ersetzt alle Vorkommen im ganzen Baum; liefert die Zahl der Ersetzungen.
    @discardableResult
    mutating func replaceAll(_ query: String, with replacement: String, options: FindOptions) -> Int {
        guard !query.isEmpty else { return 0 }
        var count = Self.replace(&text, query, replacement, options)
        if options.includeNotes { count += Self.replace(&note, query, replacement, options) }
        for i in children.indices { count += children[i].replaceAll(query, with: replacement, options: options) }
        return count
    }

    /// Ersetzt die Vorkommen in einem einzelnen Knoten.
    @discardableResult
    mutating func replace(in id: UUID, _ query: String, with replacement: String, options: FindOptions) -> Int {
        var count = 0
        updateNode(id: id) { node in
            count = Self.replace(&node.text, query, replacement, options)
            if options.includeNotes { count += Self.replace(&node.note, query, replacement, options) }
        }
        return count
    }

    private static func replace(_ string: inout String, _ query: String, _ replacement: String,
                                _ options: FindOptions) -> Int {
        var count = 0
        var searchStart = string.startIndex
        while let range = string.range(of: query, options: options.compareOptions,
                                       range: searchStart..<string.endIndex) {
            let offset = string.distance(from: string.startIndex, to: range.lowerBound) + replacement.count
            string.replaceSubrange(range, with: replacement)
            count += 1
            searchStart = string.index(string.startIndex, offsetBy: offset, limitedBy: string.endIndex)
                ?? string.endIndex
            if searchStart >= string.endIndex { break }
        }
        return count
    }

    /// Klappt alle Vorfahren eines Knotens auf (damit ein Suchtreffer sichtbar wird).
    mutating func expandAncestors(of id: UUID) {
        guard let path = path(to: id) else { return }
        for ancestor in path.dropLast() {
            updateNode(id: ancestor) { $0.isCollapsed = false }
        }
    }
}

/// Eine offene Aufgabe für die Übersicht in der Bibliothek.
struct TaskEntry: Equatable, Identifiable {
    let id: UUID
    let text: String
    /// Texte der Vorfahren, vom Hauptknoten an.
    let path: [String]
    let status: TaskStatus
}

struct FindOptions: Equatable {
    var caseSensitive = false
    var includeNotes = true

    var compareOptions: String.CompareOptions {
        caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
    }
}

struct FindMatch: Equatable {
    let id: UUID
    let inText: Bool
    let inNote: Bool
}
