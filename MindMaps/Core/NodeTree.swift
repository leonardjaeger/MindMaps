import Foundation

/// Baum-Operationen auf einem Knoten und seinen Nachfahren.
/// Alle Funktionen arbeiten rekursiv und liefern `false`/`nil`, wenn die ID nicht existiert.
extension Node {

    /// Anzahl aller Knoten inklusive dieses Knotens.
    var nodeCount: Int {
        1 + children.reduce(0) { $0 + $1.nodeCount }
    }

    /// Sucht einen Knoten im Teilbaum.
    func node(withID id: UUID) -> Node? {
        if self.id == id { return self }
        for child in children {
            if let found = child.node(withID: id) { return found }
        }
        return nil
    }

    func contains(_ id: UUID) -> Bool {
        node(withID: id) != nil
    }

    /// Kette der IDs vom aktuellen Knoten bis zum gesuchten Knoten (beide eingeschlossen).
    func path(to id: UUID) -> [UUID]? {
        if self.id == id { return [id] }
        for child in children {
            if let sub = child.path(to: id) { return [self.id] + sub }
        }
        return nil
    }

    func parentID(of id: UUID) -> UUID? {
        guard let p = path(to: id), p.count >= 2 else { return nil }
        return p[p.count - 2]
    }

    /// Ändert einen Knoten im Teilbaum.
    @discardableResult
    mutating func updateNode(id: UUID, _ change: (inout Node) -> Void) -> Bool {
        if self.id == id {
            change(&self)
            return true
        }
        for i in children.indices {
            if children[i].updateNode(id: id, change) { return true }
        }
        return false
    }

    /// Hängt einen neuen Unterknoten an. Ohne `index` landet er am Ende.
    @discardableResult
    mutating func addChild(_ child: Node, to parentID: UUID, at index: Int? = nil) -> Bool {
        updateNode(id: parentID) { parent in
            let i = min(max(index ?? parent.children.count, 0), parent.children.count)
            parent.children.insert(child, at: i)
            parent.isCollapsed = false
        }
    }

    /// Fügt einen Geschwisterknoten direkt nach `siblingID` ein.
    /// Beim Hauptknoten (ohne Eltern) wird stattdessen ein Unterknoten angelegt.
    @discardableResult
    mutating func addSibling(_ node: Node, after siblingID: UUID) -> Bool {
        guard let parent = parentID(of: siblingID) else {
            return addChild(node, to: siblingID)
        }
        return updateNode(id: parent) { p in
            let i = (p.children.firstIndex { $0.id == siblingID } ?? p.children.count - 1) + 1
            p.children.insert(node, at: i)
        }
    }

    /// Entfernt einen Knoten samt Unterknoten. Der Knoten selbst (Wurzel) kann nicht entfernt werden.
    @discardableResult
    mutating func removeNode(id: UUID) -> Node? {
        if let i = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: i)
        }
        for i in children.indices {
            if let removed = children[i].removeNode(id: id) { return removed }
        }
        return nil
    }

    /// Hängt einen Knoten um. Verhindert, dass ein Knoten in seinen eigenen Teilbaum wandert.
    @discardableResult
    mutating func moveNode(id: UUID, toParent newParentID: UUID, at index: Int? = nil) -> Bool {
        guard id != self.id,
              let moving = node(withID: id),
              !moving.contains(newParentID),
              contains(newParentID) else { return false }
        guard let removed = removeNode(id: id) else { return false }
        return addChild(removed, to: newParentID, at: index)
    }

    /// Darf `id` unter `newParentID` gehängt werden?
    /// Nicht erlaubt: den Hauptknoten, in den eigenen Teilbaum, an den bisherigen Elternknoten.
    func canMove(_ id: UUID, toParent newParentID: UUID) -> Bool {
        guard id != self.id,
              let moving = node(withID: id),
              contains(newParentID),
              !moving.contains(newParentID) else { return false }
        return parentID(of: id) != newParentID
    }

    /// Welcher Knoten nach dem Löschen von `id` ausgewählt wird:
    /// der nächste Geschwisterknoten, sonst der vorige, sonst der Elternknoten.
    func selectionAfterRemoving(_ id: UUID) -> UUID? {
        guard let pid = parentID(of: id),
              let parent = node(withID: pid),
              let i = parent.children.firstIndex(where: { $0.id == id }) else { return nil }
        if i + 1 < parent.children.count { return parent.children[i + 1].id }
        if i > 0 { return parent.children[i - 1].id }
        return pid
    }

    // MARK: - Gliederung (M3)

    /// Tab: Der Knoten wird letzter Unterknoten seines vorigen Geschwisterknotens.
    /// Geht nicht beim ersten Kind und beim Hauptknoten.
    @discardableResult
    mutating func indentNode(_ id: UUID) -> Bool {
        guard let pid = parentID(of: id),
              let parent = node(withID: pid),
              let i = parent.children.firstIndex(where: { $0.id == id }), i > 0 else { return false }
        let newParent = parent.children[i - 1].id
        guard let removed = removeNode(id: id) else { return false }
        return updateNode(id: newParent) { p in
            p.children.append(removed)
            p.isCollapsed = false
        }
    }

    /// ⇧ Tab: Der Knoten rückt eine Ebene höher und steht direkt nach seinem bisherigen Elternknoten.
    /// Geht nicht bei Ästen des Hauptknotens.
    @discardableResult
    mutating func outdentNode(_ id: UUID) -> Bool {
        guard let pid = parentID(of: id),
              let grandparent = parentID(of: pid),
              let removed = removeNode(id: id) else { return false }
        return updateNode(id: grandparent) { g in
            let i = (g.children.firstIndex { $0.id == pid } ?? g.children.count - 1) + 1
            g.children.insert(removed, at: min(i, g.children.count))
        }
    }

    /// Darf `id` direkt vor oder nach `targetID` (als dessen Geschwister) einsortiert werden?
    func canMove(_ id: UUID, beside targetID: UUID) -> Bool {
        guard id != self.id, id != targetID, targetID != self.id,
              let moving = node(withID: id),
              !moving.contains(targetID),
              contains(targetID) else { return false }
        return true
    }

    /// Sortiert `id` (samt Unterknoten) direkt vor oder nach `targetID` ein – für Drag & Drop in der Outline.
    @discardableResult
    mutating func moveNode(_ id: UUID, beside targetID: UUID, after: Bool) -> Bool {
        guard canMove(id, beside: targetID),
              let parent = parentID(of: targetID),
              let removed = removeNode(id: id) else { return false }
        return updateNode(id: parent) { p in
            let i = p.children.firstIndex { $0.id == targetID } ?? p.children.count
            p.children.insert(removed, at: after ? min(i + 1, p.children.count) : i)
        }
    }

    /// Kann der Knoten ein- oder ausgeklappt werden? (Nicht der Hauptknoten, nur Knoten mit Unterknoten.)
    func canToggleCollapse(_ id: UUID) -> Bool {
        guard id != self.id, let node = node(withID: id) else { return false }
        return !node.children.isEmpty
    }

    /// Der Knoten selbst – oder, wenn ein Vorfahr eingeklappt ist, der oberste eingeklappte Vorfahr
    /// (also der Knoten, der an seiner Stelle zu sehen ist).
    func visibleNode(for id: UUID) -> UUID? {
        guard let path = path(to: id) else { return nil }
        for ancestor in path.dropLast() where node(withID: ancestor)?.isCollapsed == true {
            return ancestor
        }
        return id
    }

    /// Sichtbare Knoten in Lesereihenfolge (eingeklappte Teilbäume ausgelassen) – für die Outline.
    func visibleRows(depth: Int = 0) -> [OutlineRow] {
        var rows = [OutlineRow(id: id, depth: depth, text: text,
                               hasChildren: !children.isEmpty, isCollapsed: isCollapsed,
                               hasNote: !note.isEmpty, tags: tags, taskStatus: taskStatus,
                               hasTaskMark: task != nil,
                               hasLink: !link.isEmpty,
                               taskProgress: hasTaskDescendants ? taskProgress : nil)]
        if !isCollapsed {
            for child in children { rows += child.visibleRows(depth: depth + 1) }
        }
        return rows
    }
}

/// Eine Zeile der Outline-Ansicht.
struct OutlineRow: Identifiable, Equatable {
    let id: UUID
    let depth: Int
    let text: String
    let hasChildren: Bool
    let isCollapsed: Bool
    var hasNote = false
    var tags: [String] = []
    var taskStatus: TaskStatus?
    /// Ist selbst eine Aufgabe (nicht nur Zweig mit Aufgaben darunter).
    var hasTaskMark = false
    var hasLink = false
    /// Erledigt/gesamt, wenn Aufgaben darunter liegen.
    var taskProgress: (done: Int, total: Int)?

    static func == (a: OutlineRow, b: OutlineRow) -> Bool {
        a.id == b.id && a.depth == b.depth && a.text == b.text && a.hasChildren == b.hasChildren
            && a.isCollapsed == b.isCollapsed && a.hasNote == b.hasNote && a.tags == b.tags
            && a.taskStatus == b.taskStatus && a.hasTaskMark == b.hasTaskMark && a.hasLink == b.hasLink && a.taskProgress?.done == b.taskProgress?.done
            && a.taskProgress?.total == b.taskProgress?.total
    }
}
