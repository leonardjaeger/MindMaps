import Foundation

/// Abgleich der Aufgaben eines Dokuments mit einer Liste in Apples Erinnerungen (M9).
///
/// Hier steht nur die Logik – ohne EventKit, damit sie getestet werden kann. Die App liest die
/// Erinnerungen, lässt sich einen `RemindersSyncPlan` berechnen und führt ihn aus.
///
/// Regeln:
/// - Jede Aufgabe der Map bekommt eine Erinnerung. Die Erinnerung trägt einen `mindmaps://`-Link
///   auf ihren Knoten – daran erkennt der Abgleich, welche Erinnerung zu welchem Knoten gehört.
/// - Abhaken und Text: Geändert hat, wer vom letzten Abgleich abweicht (Dreiwegevergleich).
///   So kommt ein Häkchen aus Erinnerungen in die Map und umgekehrt, und Rückgängig in der App wirkt auch dort.
/// - Aufgabe in der Map gelöscht oder keine Aufgabe mehr → ihre Erinnerung wird entfernt.
/// - Erinnerung in Erinnerungen gelöscht → sie wird nicht neu angelegt, die Aufgabe bleibt in der Map.
/// - Neue Erinnerung in der Liste (ohne Link) → neue Aufgabe unter dem Hauptknoten.
enum RemindersSync {
    /// Eine Aufgabe der Map, wie der Abgleich sie sieht.
    struct Task: Equatable {
        let id: UUID
        /// Text des Knotens (leer wird zu „Ohne Titel“).
        let title: String
        let done: Bool
        /// Weg zum Knoten, z. B. „Referat › Gliederung“ – steht als Notiz an der Erinnerung.
        let context: String
    }

    /// Eine Erinnerung der Liste.
    struct Reminder: Equatable {
        /// `calendarItemIdentifier` von EventKit.
        let id: String
        let title: String
        let done: Bool
        /// Adresse der Erinnerung (bei unseren: `mindmaps://open?file=…&node=…`).
        let url: String?

        var nodeID: UUID? { url.flatMap(DocumentLink.parse)?.node }
    }

    /// Was sich der Abgleich pro Liste merkt (liegt in der App, nicht im Dokument –
    /// sonst würde Rückgängig in der App den Abgleich durcheinanderbringen).
    struct State: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var title: String
            var done: Bool
        }
        /// Stand beim letzten Abgleich, pro Knoten.
        var entries: [UUID: Entry] = [:]
        /// Knoten, deren Erinnerung in Erinnerungen gelöscht wurde – werden nicht neu angelegt.
        var removedInReminders: Set<UUID> = []
    }

    struct ReminderChange: Equatable {
        let reminderID: String
        var title: String?
        var done: Bool?
        /// Neuer Link (Knoten verschoben, Dokument umbenannt oder Erinnerung neu verknüpft).
        var url: String?
    }

    struct NodeChange: Equatable {
        let nodeID: UUID
        var title: String?
        var done: Bool?
    }

    /// Aufgabe, die aus einer neuen Erinnerung entsteht.
    struct NewTask: Equatable {
        let nodeID: UUID
        let reminderID: String
        let title: String
        let done: Bool
    }

    struct Plan: Equatable {
        var create: [Task] = []
        var update: [ReminderChange] = []
        var remove: [String] = []
        var nodeChanges: [NodeChange] = []
        var newTasks: [NewTask] = []
        var state = State()

        /// Muss in Erinnerungen etwas geändert werden?
        var changesReminders: Bool { !create.isEmpty || !update.isEmpty || !remove.isEmpty }
        /// Muss im Dokument etwas geändert werden?
        var changesDocument: Bool { !nodeChanges.isEmpty || !newTasks.isEmpty }
        var isEmpty: Bool { !changesReminders && !changesDocument }
    }

    static let untitled = L("Ohne Titel")

    /// Alle Aufgaben des Dokuments in Lesereihenfolge. Eine Aufgabe mit Unteraufgaben gilt als erledigt,
    /// wenn alle Unteraufgaben erledigt sind (wie in der Map).
    static func tasks(in root: Node, documentTitle: String) -> [Task] {
        var result: [Task] = []
        func visit(_ node: Node, _ path: [String]) {
            if node.task != nil {
                let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
                result.append(Task(id: node.id,
                                   title: text.isEmpty ? untitled : text,
                                   done: node.taskStatus == .done,
                                   context: (path.isEmpty ? [documentTitle] : path).joined(separator: " › ")))
            }
            let name = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            for child in node.children { visit(child, path + [name.isEmpty ? untitled : name]) }
        }
        visit(root, [])
        return result
    }

    /// Link, den die Erinnerung einer Aufgabe tragen soll.
    static func link(for nodeID: UUID, file: URL) -> String {
        DocumentLink.make(file: file, node: nodeID)
    }

    /// Berechnet, was zu tun ist. `newNodeID` erzeugt IDs für Aufgaben aus neuen Erinnerungen (Tests: fest).
    static func plan(tasks: [Task], reminders: [Reminder], state: State, file: URL,
                     newNodeID: () -> UUID = { UUID() }) -> Plan {
        var plan = Plan()
        let taskIDs = Set(tasks.map(\.id))

        // Erinnerungen nach Knoten; doppelte (z. B. nach einem abgebrochenen Abgleich) werden entfernt.
        var byNode: [UUID: Reminder] = [:]
        var foreign: [Reminder] = []
        for reminder in reminders {
            if let node = reminder.nodeID {
                if byNode[node] == nil {
                    byNode[node] = reminder
                } else {
                    plan.remove.append(reminder.id)
                }
            } else {
                foreign.append(reminder)
            }
        }

        for task in tasks {
            let expectedLink = link(for: task.id, file: file)
            guard let reminder = byNode[task.id] else {
                if state.removedInReminders.contains(task.id) || state.entries[task.id] != nil {
                    // In Erinnerungen gelöscht: nicht wieder anlegen.
                    plan.state.removedInReminders.insert(task.id)
                } else {
                    plan.create.append(task)
                    plan.state.entries[task.id] = .init(title: task.title, done: task.done)
                }
                continue
            }

            let last = state.entries[task.id] ?? .init(title: task.title, done: task.done)
            var done = task.done
            if task.done == last.done, reminder.done != last.done { done = reminder.done }
            var title = task.title
            if task.title == last.title, reminder.title != last.title,
               !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = reminder.title
            }

            var change = ReminderChange(reminderID: reminder.id)
            if reminder.done != done { change.done = done }
            if reminder.title != title { change.title = title }
            if reminder.url != expectedLink { change.url = expectedLink }
            if change.done != nil || change.title != nil || change.url != nil { plan.update.append(change) }

            var nodeChange = NodeChange(nodeID: task.id)
            if task.done != done { nodeChange.done = done }
            if task.title != title { nodeChange.title = title }
            if nodeChange.done != nil || nodeChange.title != nil { plan.nodeChanges.append(nodeChange) }

            plan.state.entries[task.id] = .init(title: title, done: done)
        }

        // Erinnerungen, deren Knoten keine Aufgabe (mehr) ist.
        for (node, reminder) in byNode where !taskIDs.contains(node) {
            if state.entries[node] != nil {
                // Von uns angelegt, Aufgabe in der Map entfernt → Erinnerung entfernen.
                plan.remove.append(reminder.id)
            } else {
                // Verweist auf einen fremden Knoten (z. B. aus einem anderen Dokument hineingezogen) → übernehmen.
                foreign.append(reminder)
            }
        }

        // Neue Erinnerungen → neue Aufgaben unter dem Hauptknoten, danach mit Link.
        for reminder in foreign.sorted(by: { $0.id < $1.id }) {
            let id = newNodeID()
            let title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.newTasks.append(NewTask(nodeID: id, reminderID: reminder.id,
                                         title: title.isEmpty ? untitled : title, done: reminder.done))
            plan.update.append(ReminderChange(reminderID: reminder.id, url: link(for: id, file: file)))
            plan.state.entries[id] = .init(title: title.isEmpty ? untitled : title, done: reminder.done)
        }

        plan.remove.sort()
        return plan
    }
}

// MARK: - Plan auf das Dokument anwenden

extension MindMapDocumentData {
    /// Übernimmt Änderungen aus Erinnerungen: Häkchen, Texte und neue Aufgaben.
    mutating func applyReminderChanges(_ plan: RemindersSync.Plan) {
        for change in plan.nodeChanges {
            root.updateNode(id: change.nodeID) { node in
                if let title = change.title { node.text = title }
                if let done = change.done { node.setTaskDone(done) }
            }
        }
        let rootID = root.id
        for task in plan.newTasks {
            root.addChild(Node(id: task.nodeID, text: task.title, task: task.done ? .done : .open), to: rootID)
        }
    }
}

/// Verknüpfung eines Dokuments mit einer Liste in Erinnerungen (im Dokument gespeichert).
struct RemindersLink: Codable, Equatable {
    /// `calendarIdentifier` der Liste.
    var listID: String
    /// Name der Liste beim Einrichten (zur Anzeige).
    var listTitle: String
}
