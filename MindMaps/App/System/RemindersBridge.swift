import AppKit
import EventKit

/// Zugriff auf Apples Erinnerungen (EventKit) – einmal für die ganze App (M9).
@MainActor
final class RemindersAccess {
    static let shared = RemindersAccess()
    let store = EKEventStore()

    enum AccessError: LocalizedError {
        case denied
        case noAccount
        var errorDescription: String? {
            switch self {
            case .denied:
                return L("MindMaps darf nicht auf Erinnerungen zugreifen. Erlaube es unter Systemeinstellungen › Datenschutz & Sicherheit › Erinnerungen.")
            case .noAccount:
                return L("In Erinnerungen gibt es keinen Account, in dem eine Liste angelegt werden kann.")
            }
        }
    }

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    /// Fragt beim ersten Mal nach der Erlaubnis (Dialog von macOS).
    func requestAccess() async -> Bool {
        if isAuthorized { return true }
        do {
            return try await store.requestFullAccessToReminders()
        } catch {
            return false
        }
    }

    func list(withID id: String) -> EKCalendar? {
        store.calendar(withIdentifier: id)
    }

    /// Neue Liste im Standard-Account (meist iCloud). Gibt es den Namen schon, wird nummeriert.
    func createList(named title: String) throws -> EKCalendar {
        let taken = Set(store.calendars(for: .reminder).map(\.title))
        var name = title
        var number = 2
        while taken.contains(name) {
            name = "\(title) \(number)"
            number += 1
        }
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local }) else {
            throw AccessError.noAccount
        }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = name
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    func reminders(in list: EKCalendar) async -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }
}

/// Was sich der Abgleich pro Liste merkt – in den App-Einstellungen, nicht im Dokument.
enum RemindersSyncStore {
    private static func key(_ listID: String) -> String { "remindersSync." + listID }

    static func load(_ listID: String) -> RemindersSync.State {
        guard let data = UserDefaults.standard.data(forKey: key(listID)),
              let state = try? JSONDecoder().decode(RemindersSync.State.self, from: data) else { return .init() }
        return state
    }

    static func save(_ state: RemindersSync.State, listID: String) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: key(listID))
        }
    }
}

/// Gleicht die Aufgaben eines offenen Dokuments mit seiner Liste in Erinnerungen ab (M9).
///
/// Läuft, solange das Fenster offen ist: nach Änderungen im Dokument, nach Änderungen in Erinnerungen
/// (auch auf dem iPhone, sobald iCloud sie liefert) und wenn die App wieder aktiv wird.
@MainActor
final class RemindersSyncController: ObservableObject {
    enum Status: Equatable {
        case off
        case syncing
        case synced(Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .off

    private weak var document: MindMapFile?
    private var fileURL: URL?
    private weak var undoManager: UndoManager?
    private var observers: [NSObjectProtocol] = []
    private var scheduled: DispatchWorkItem?
    private var isRunning = false
    private var runAgain = false

    private var access: RemindersAccess { .shared }

    /// Fenster geöffnet bzw. Speicherort geändert.
    func attach(document: MindMapFile, fileURL: URL?, undoManager: UndoManager?) {
        self.document = document
        self.fileURL = fileURL
        self.undoManager = undoManager
        if observers.isEmpty {
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .EKEventStoreChanged, object: access.store,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule(after: 0.5) }
            })
            observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule(after: 0.2) }
            })
        }
        schedule(after: 0.3)
    }

    func detach() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        scheduled?.cancel()
        document = nil
    }

    /// Nach einer Änderung im Dokument (gebündelt, damit nicht jeder Tastendruck abgleicht).
    func documentChanged() {
        schedule(after: 1.0)
    }

    private func schedule(after delay: TimeInterval) {
        guard document?.data.reminders != nil else {
            status = .off
            return
        }
        scheduled?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.syncNow() }
            }
        }
        scheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Ein- und ausschalten

    /// „Aufgaben mit Erinnerungen abgleichen“ einschalten: Erlaubnis holen, Liste anlegen, abgleichen.
    /// Liefert eine Erklärung, wenn es nicht geht.
    @discardableResult
    func enable(actions: DocumentActions) async -> String? {
        guard let document else { return nil }
        guard let fileURL else {
            return L("Sichere das Dokument zuerst – die Erinnerungen verweisen auf die Datei.")
        }
        guard await access.requestAccess() else {
            let message = RemindersAccess.AccessError.denied.localizedDescription
            status = .failed(message)
            return message
        }
        do {
            let list = try access.createList(named: fileURL.deletingPathExtension().lastPathComponent)
            RemindersSyncStore.save(.init(), listID: list.calendarIdentifier)
            let link = RemindersLink(listID: list.calendarIdentifier, listTitle: list.title)
            if document.data.reminders != nil {
                actions.setRemindersLink(link, actionName: "Neue Liste in Erinnerungen")
            } else {
                actions.setRemindersLink(link)
            }
            await syncNow()
            return nil
        } catch {
            status = .failed(error.localizedDescription)
            return error.localizedDescription
        }
    }

    /// Abgleich beenden. Die Liste in Erinnerungen bleibt, wie sie ist.
    func disable(actions: DocumentActions) {
        actions.setRemindersLink(nil)
        scheduled?.cancel()
        status = .off
    }

    /// „Erneut versuchen“ im Hinweis: Ohne Erlaubnis oder ohne Liste wird neu eingerichtet.
    func retry(actions: DocumentActions) async {
        guard let link = document?.data.reminders else { return }
        if access.isAuthorized, access.list(withID: link.listID) != nil {
            await syncNow()
        } else {
            await enable(actions: actions)
        }
    }

    // MARK: - Abgleich

    func syncNow() async {
        guard let document, let link = document.data.reminders else {
            status = .off
            return
        }
        guard let fileURL else {
            status = .failed(L("Sichere das Dokument zuerst – die Erinnerungen verweisen auf die Datei."))
            return
        }
        guard access.isAuthorized else {
            status = .failed(RemindersAccess.AccessError.denied.localizedDescription)
            return
        }
        guard let list = access.list(withID: link.listID) else {
            status = .failed(L("Die Liste „%@“ gibt es in Erinnerungen nicht mehr.", link.listTitle))
            return
        }
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        if case .synced = status {} else { status = .syncing }

        let items = await access.reminders(in: list)

        // Nach dem Warten mit dem aktuellen Stand des Dokuments rechnen.
        let data = document.data
        let title = fileURL.deletingPathExtension().lastPathComponent
        let tasks = RemindersSync.tasks(in: data.root, documentTitle: title)
        let snapshots = items.map {
            RemindersSync.Reminder(id: $0.calendarItemIdentifier, title: $0.title ?? "",
                                   done: $0.isCompleted, url: $0.url?.absoluteString)
        }
        let plan = RemindersSync.plan(tasks: tasks, reminders: snapshots,
                                      state: RemindersSyncStore.load(link.listID), file: fileURL)
        do {
            try write(plan, to: list, existing: items, file: fileURL)
            if plan.changesDocument {
                document.apply(L("Aus Erinnerungen übernehmen"), undoManager: undoManager) { data in
                    data.applyReminderChanges(plan)
                }
            }
            RemindersSyncStore.save(plan.state, listID: link.listID)
            status = .synced(Date())
        } catch {
            access.store.reset()
            status = .failed(L("Abgleich mit Erinnerungen fehlgeschlagen: %@", error.localizedDescription))
        }

        isRunning = false
        if runAgain {
            runAgain = false
            schedule(after: 0.3)
        }
    }

    private func write(_ plan: RemindersSync.Plan, to list: EKCalendar, existing: [EKReminder], file: URL) throws {
        guard plan.changesReminders else { return }
        let store = access.store
        var byID: [String: EKReminder] = [:]
        for reminder in existing where byID[reminder.calendarItemIdentifier] == nil {
            byID[reminder.calendarItemIdentifier] = reminder
        }
        for task in plan.create {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = task.title
            reminder.isCompleted = task.done
            reminder.url = URL(string: RemindersSync.link(for: task.id, file: file))
            reminder.notes = L("Aus MindMaps: %@", task.context)
            try store.save(reminder, commit: false)
        }
        for change in plan.update {
            guard let reminder = byID[change.reminderID] else { continue }
            if let title = change.title { reminder.title = title }
            if let done = change.done { reminder.isCompleted = done }
            if let url = change.url { reminder.url = URL(string: url) }
            try store.save(reminder, commit: false)
        }
        for id in plan.remove {
            guard let reminder = byID[id] else { continue }
            try store.remove(reminder, commit: false)
        }
        try store.commit()
    }
}
