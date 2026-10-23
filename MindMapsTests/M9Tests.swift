import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M9: Abgleich mit Erinnerungen, Spotlight, Kurzbefehle.
final class M9Tests: XCTestCase {

    // MARK: - Hilfen

    private static let file = URL(fileURLWithPath: "/Users/test/MindMaps/Referat.mindmaps")

    /// Referat › Gliederung › (Einleitung ✓, Hauptteil), Material › Quellen, Vortrag üben
    private static func sample() -> (data: MindMapDocumentData, ids: [String: UUID]) {
        let einleitung = Node(text: "Einleitung", task: .done)
        let hauptteil = Node(text: "Hauptteil", task: .open)
        let gliederung = Node(text: "Gliederung", children: [einleitung, hauptteil], task: .open)
        let quellen = Node(text: "Quellen", task: .open)
        let material = Node(text: "Material", children: [quellen])
        let ueben = Node(text: "", task: .open)
        let root = Node(text: "Referat", children: [gliederung, material, ueben])
        return (MindMapDocumentData(root: root),
                ["einleitung": einleitung.id, "hauptteil": hauptteil.id, "gliederung": gliederung.id,
                 "quellen": quellen.id, "ueben": ueben.id, "material": material.id])
    }

    private static func tasks(_ data: MindMapDocumentData) -> [RemindersSync.Task] {
        RemindersSync.tasks(in: data.root, documentTitle: "Referat")
    }

    /// Erinnerungen so, wie sie nach einem Abgleich in der Liste stehen.
    private static func reminders(for plan: RemindersSync.Plan, file: URL = file) -> [RemindersSync.Reminder] {
        plan.create.map {
            RemindersSync.Reminder(id: "r-" + $0.id.uuidString, title: $0.title, done: $0.done,
                                   url: RemindersSync.link(for: $0.id, file: file))
        }
    }

    private static func replacing(_ reminders: [RemindersSync.Reminder], node: UUID,
                                  title: String? = nil, done: Bool? = nil) -> [RemindersSync.Reminder] {
        reminders.map { r in
            guard r.nodeID == node else { return r }
            return RemindersSync.Reminder(id: r.id, title: title ?? r.title, done: done ?? r.done, url: r.url)
        }
    }

    // MARK: - Erinnerungen

    func testFirstSyncCreatesOneReminderPerTask() {
        let (data, ids) = Self.sample()
        let plan = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: .init(), file: Self.file)

        XCTAssertEqual(plan.create.map(\.id), [ids["gliederung"]!, ids["einleitung"]!, ids["hauptteil"]!,
                                               ids["quellen"]!, ids["ueben"]!], "Lesereihenfolge, ohne Nicht-Aufgaben")
        XCTAssertTrue(plan.update.isEmpty && plan.remove.isEmpty && !plan.changesDocument)
        let byID = Dictionary(uniqueKeysWithValues: plan.create.map { ($0.id, $0) })
        XCTAssertEqual(byID[ids["einleitung"]!]?.done, true)
        XCTAssertEqual(byID[ids["gliederung"]!]?.done, false, "teilweise erledigt = offen")
        XCTAssertEqual(byID[ids["ueben"]!]?.title, RemindersSync.untitled)
        XCTAssertEqual(byID[ids["quellen"]!]?.context, "Referat › Material")
        XCTAssertEqual(byID[ids["gliederung"]!]?.context, "Referat")
        XCTAssertEqual(plan.state.entries.count, 5)

        // Der Link führt zurück zum Knoten.
        let link = RemindersSync.link(for: ids["quellen"]!, file: Self.file)
        XCTAssertEqual(DocumentLink.parse(link)?.node, ids["quellen"]!)
        XCTAssertEqual(DocumentLink.parse(link)?.file.path, Self.file.path)

        // Zweiter Abgleich ohne Änderungen: nichts zu tun.
        let again = RemindersSync.plan(tasks: Self.tasks(data), reminders: Self.reminders(for: plan),
                                       state: plan.state, file: Self.file)
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(again.state, plan.state)
    }

    func testCheckingInRemindersChecksTheTaskInTheMap() {
        var (data, ids) = Self.sample()
        let first = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: .init(), file: Self.file)
        let hauptteil = ids["hauptteil"]!
        let checked = Self.replacing(Self.reminders(for: first), node: hauptteil, done: true)

        let plan = RemindersSync.plan(tasks: Self.tasks(data), reminders: checked, state: first.state, file: Self.file)
        XCTAssertEqual(plan.nodeChanges, [RemindersSync.NodeChange(nodeID: hauptteil, title: nil, done: true)])
        XCTAssertTrue(plan.update.isEmpty, "Erinnerung ist schon abgehakt")

        data.applyReminderChanges(plan)
        XCTAssertEqual(data.root.node(withID: hauptteil)?.task, .done)
        // Damit ist die ganze Gliederung erledigt – das geht beim nächsten Abgleich an Erinnerungen.
        XCTAssertEqual(data.root.node(withID: ids["gliederung"]!)?.taskStatus, .done)
        let next = RemindersSync.plan(tasks: Self.tasks(data), reminders: checked, state: plan.state, file: Self.file)
        XCTAssertEqual(next.update.map(\.done), [true])
        XCTAssertEqual(next.update.first?.reminderID, "r-" + ids["gliederung"]!.uuidString)
        XCTAssertTrue(next.nodeChanges.isEmpty)

        // Wieder öffnen in Erinnerungen öffnet auch die Aufgaben darunter.
        let reopened = Self.replacing(Self.replacing(checked, node: ids["gliederung"]!, done: false),
                                      node: hauptteil, done: true)
        let reopen = RemindersSync.plan(tasks: Self.tasks(data), reminders: reopened, state: next.state, file: Self.file)
        data.applyReminderChanges(reopen)
        XCTAssertEqual(data.root.node(withID: ids["einleitung"]!)?.task, .open)
    }

    func testCheckingInTheMapChecksTheReminderAndUndoWorksToo() {
        var (data, ids) = Self.sample()
        let first = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: .init(), file: Self.file)
        let reminders = Self.reminders(for: first)
        let quellen = ids["quellen"]!

        data.root.toggleDone(quellen)
        let plan = RemindersSync.plan(tasks: Self.tasks(data), reminders: reminders, state: first.state, file: Self.file)
        XCTAssertEqual(plan.update, [RemindersSync.ReminderChange(reminderID: "r-" + quellen.uuidString, title: nil,
                                                                  done: true, url: nil)])
        XCTAssertFalse(plan.changesDocument)

        // Rückgängig in der App (Aufgabe wieder offen), nachdem die Erinnerung abgehakt wurde.
        let synced = Self.replacing(reminders, node: quellen, done: true)
        data.root.toggleDone(quellen)
        let undo = RemindersSync.plan(tasks: Self.tasks(data), reminders: synced, state: plan.state, file: Self.file)
        XCTAssertEqual(undo.update.first?.done, false)
        XCTAssertFalse(undo.changesDocument, "Die App gewinnt – das Häkchen kommt nicht zurück")
    }

    func testTextsGoBothWaysAndLinksFollowTheFile() {
        var (data, ids) = Self.sample()
        let first = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: .init(), file: Self.file)
        var reminders = Self.reminders(for: first)
        let quellen = ids["quellen"]!, hauptteil = ids["hauptteil"]!

        // In der Map umbenannt → Erinnerung bekommt den neuen Text.
        data.root.updateNode(id: quellen) { $0.text = "Quellen prüfen" }
        // In Erinnerungen umbenannt → Knoten bekommt den neuen Text.
        reminders = Self.replacing(reminders, node: hauptteil, title: "Hauptteil schreiben")
        let plan = RemindersSync.plan(tasks: Self.tasks(data), reminders: reminders, state: first.state, file: Self.file)
        XCTAssertEqual(plan.update.map(\.title), ["Quellen prüfen"])
        XCTAssertEqual(plan.nodeChanges.map(\.title), ["Hauptteil schreiben"])
        data.applyReminderChanges(plan)
        XCTAssertEqual(data.root.node(withID: hauptteil)?.text, "Hauptteil schreiben")

        // Datei umbenannt: Links werden nachgezogen, sonst ändert sich nichts.
        let moved = URL(fileURLWithPath: "/Users/test/MindMaps/Studium/Referat Lernen.mindmaps")
        reminders = Self.replacing(reminders, node: quellen, title: "Quellen prüfen")
        let relink = RemindersSync.plan(tasks: Self.tasks(data), reminders: reminders, state: plan.state, file: moved)
        XCTAssertEqual(relink.update.count, 5)
        XCTAssertTrue(relink.update.allSatisfy { $0.url != nil && $0.title == nil && $0.done == nil })
        XCTAssertEqual(DocumentLink.parse(relink.update[0].url!)?.file.path, moved.path)
        XCTAssertFalse(relink.changesDocument)
    }

    func testDeletedTasksDeletedRemindersAndNewReminders() {
        var (data, ids) = Self.sample()
        let first = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: .init(), file: Self.file)
        var reminders = Self.reminders(for: first)
        let quellen = ids["quellen"]!, ueben = ids["ueben"]!

        // Aufgabe in der Map entfernt → Erinnerung weg.
        data.root.toggleTask(quellen)
        // Erinnerung in Erinnerungen gelöscht → bleibt weg, Aufgabe bleibt in der Map.
        reminders.removeAll { $0.nodeID == ueben }
        // Neue Erinnerung in der Liste (z. B. per Siri auf dem iPhone).
        reminders.append(.init(id: "neu-1", title: "Handout drucken", done: false, url: nil))
        // Doppelte Erinnerung (abgebrochener Abgleich) wird aufgeräumt.
        let hauptteil = ids["hauptteil"]!
        reminders.append(.init(id: "zz-doppelt", title: "Hauptteil", done: false,
                               url: RemindersSync.link(for: hauptteil, file: Self.file)))

        let newID = UUID()
        let plan = RemindersSync.plan(tasks: Self.tasks(data), reminders: reminders, state: first.state,
                                      file: Self.file, newNodeID: { newID })
        XCTAssertEqual(plan.remove, ["r-" + quellen.uuidString, "zz-doppelt"])
        XCTAssertTrue(plan.create.isEmpty, "gelöschte Erinnerung wird nicht neu angelegt")
        XCTAssertTrue(plan.state.removedInReminders.contains(ueben))
        XCTAssertEqual(plan.newTasks, [.init(nodeID: newID, reminderID: "neu-1", title: "Handout drucken", done: false)])
        XCTAssertEqual(plan.update, [.init(reminderID: "neu-1", title: nil, done: nil,
                                           url: RemindersSync.link(for: newID, file: Self.file))])

        data.applyReminderChanges(plan)
        let added = data.root.node(withID: newID)
        XCTAssertEqual(added?.text, "Handout drucken")
        XCTAssertEqual(added?.task, .open)
        XCTAssertEqual(data.root.parentID(of: newID), data.root.id)
        XCTAssertEqual(data.root.node(withID: ueben)?.task, .open)

        // Auch später wird die gelöschte Erinnerung nicht wieder angelegt.
        let later = RemindersSync.plan(tasks: Self.tasks(data), reminders: [], state: plan.state, file: Self.file)
        XCTAssertFalse(later.create.contains { $0.id == ueben })
    }

    func testRemindersLinkIsSavedWithTheDocument() throws {
        var (data, _) = Self.sample()
        let plain = try MindMapCodec.encode(data)
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("reminders"), "aus = nicht in der Datei")
        data.reminders = RemindersLink(listID: "ABC-123", listTitle: "Referat")
        let decoded = try MindMapCodec.decode(MindMapCodec.encode(data))
        XCTAssertEqual(decoded.reminders, data.reminders)
        XCTAssertEqual(decoded, data)

        // Der Merkzettel des Abgleichs lässt sich speichern.
        var state = RemindersSync.State()
        state.entries[UUID()] = .init(title: "A", done: true)
        state.removedInReminders.insert(UUID())
        XCTAssertEqual(try JSONDecoder().decode(RemindersSync.State.self, from: JSONEncoder().encode(state)), state)
    }

    // MARK: - Spotlight

    func testSpotlightSeesAllNodeTextsNotesAndTags() {
        var (data, ids) = Self.sample()
        data.root.updateNode(id: ids["quellen"]!) { node in
            node.note = "Bibliothek: **Fernleihe** bestellen"
            node.tags = ["Wichtig"]
        }
        data.root.updateNode(id: ids["material"]!) { $0.formula = "E = mc^2" }
        let content = SpotlightContent.make(title: "Referat Lerntheorien", data: data)
        XCTAssertEqual(content.title, "Referat Lerntheorien")
        for word in ["Referat", "Gliederung", "Einleitung", "Hauptteil", "Quellen", "Fernleihe", "E = mc^2"] {
            XCTAssertTrue(content.text.contains(word), word)
        }
        XCTAssertEqual(content.keywords, ["Referat", "Wichtig"])
        XCTAssertEqual(content.summary, "Referat: Gliederung · Material")

        let reference = SpotlightContent.make(title: "Referenz", data: CoreTests.referenceDocument())
        XCTAssertEqual(reference.text.components(separatedBy: "\n").count, 53, "ein Eintrag pro Knoten")
    }

    // MARK: - Kurzbefehle: Knoten in eine geschlossene Datei

    func testAddingNodesToAClosedFileKeepsEverythingElse() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("M9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = folder.appendingPathComponent("Einkauf.mindmaps")
        let assets = package.appendingPathComponent(MindMapCodec.assetsFolderName)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let image = Data([1, 2, 3, 4])
        try image.write(to: assets.appendingPathComponent("bild.png"))

        var (data, ids) = Self.sample()
        data.createdAt = Date(timeIntervalSince1970: 1_000_000)
        data.modifiedAt = data.createdAt
        data.root.updateNode(id: ids["material"]!) { $0.isCollapsed = true }
        try MindMapPackage.write(data, to: package)

        var loaded = try MindMapPackage.read(package)
        let first = try MindMapPackage.addNode("  Folien  ", asTask: true, under: "material", to: &loaded)
        let second = try MindMapPackage.addNode("Fazit", asTask: false, under: "gibt es nicht", to: &loaded)
        XCTAssertThrowsError(try MindMapPackage.addNode("   ", asTask: false, under: nil, to: &loaded))
        try MindMapPackage.write(loaded, to: package)

        let result = try MindMapPackage.read(package)
        XCTAssertEqual(result.root.parentID(of: first), ids["material"])
        XCTAssertEqual(result.root.node(withID: first)?.text, "Folien")
        XCTAssertEqual(result.root.node(withID: first)?.task, .open)
        XCTAssertEqual(result.root.node(withID: ids["material"]!)?.isCollapsed, false, "neuer Knoten ist sichtbar")
        XCTAssertEqual(result.root.parentID(of: second), result.root.id, "unbekannter Elternknoten → Hauptknoten")
        XCTAssertNil(result.root.node(withID: second)?.task)
        XCTAssertEqual(result.root.nodeCount, data.root.nodeCount + 2)
        XCTAssertEqual(result.createdAt, data.createdAt)
        XCTAssertGreaterThan(result.modifiedAt, data.modifiedAt)
        XCTAssertEqual(try Data(contentsOf: assets.appendingPathComponent("bild.png")), image, "Bilder bleiben")

        XCTAssertThrowsError(try MindMapPackage.read(folder.appendingPathComponent("Fehlt.mindmaps"))) { error in
            XCTAssertEqual(error as? MindMapPackage.PackageError, .notFound("Fehlt"))
        }
    }

    #if canImport(AppKit)

    // MARK: - Nur auf dem Mac: Kurzbefehle mit App-Teilen

    private static func libraryDocument(_ title: String, _ root: Node, modified: TimeInterval) -> LibraryDocument {
        LibraryDocument(url: URL(fileURLWithPath: "/tmp/\(title).mindmaps"), title: title,
                        modified: Date(timeIntervalSince1970: modified), data: MindMapDocumentData(root: root))
    }

    @MainActor
    func testSearchPutsTitlesFirstAndFindsNodeTexts() {
        let docs = [
            Self.libraryDocument("Biologie", Node(text: "Zelle", children: [Node(text: "Mitochondrien")]), modified: 1),
            Self.libraryDocument("Zellbiologie", Node(text: "Überblick"), modified: 2),
            Self.libraryDocument("Chemie", Node(text: "Zellmembran"), modified: 3),
            Self.libraryDocument("Geschichte", Node(text: "Rom"), modified: 4),
        ]
        XCTAssertEqual(MindMapCatalog.search("zell", in: docs).map(\.title), ["Zellbiologie", "Chemie", "Biologie"])
        XCTAssertEqual(MindMapCatalog.search("mitochondrien", in: docs).map(\.title), ["Biologie"])
        XCTAssertEqual(MindMapCatalog.search("", in: docs).first?.title, "Geschichte", "leer = neueste zuerst")
        XCTAssertTrue(MindMapCatalog.search("Physik", in: docs).isEmpty)
    }

    @MainActor
    func testLastDocumentAsPDFForTheShortcut() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("M9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let older = try LibraryStore.createDocument(CoreTests.referenceDocument(), named: "Referenz", in: folder)
        let newer = try LibraryStore.createDocument(Self.sample().data, named: "Referat", in: folder)
        let missing = folder.appendingPathComponent("Gelöscht.mindmaps")
        let docs = [LibraryScanner.loadDocument(at: older)!, LibraryScanner.loadDocument(at: newer)!]

        // „Zuletzt benutzt“ von macOS zählt vor dem Änderungsdatum; gelöschte Dateien werden übersprungen.
        XCTAssertEqual(MindMapCatalog.lastUsed(recent: [missing, older], documents: docs), older)
        XCTAssertNotNil(MindMapCatalog.lastUsed(recent: [], documents: docs))
        XCTAssertNil(MindMapCatalog.lastUsed(recent: [], documents: []))

        let pdf = try ShortcutSupport.export(older, format: .pdf, singlePage: false)
        XCTAssertEqual(pdf.filename, "Referenz.pdf")
        XCTAssertTrue(pdf.data.starts(with: Data("%PDF".utf8)))
        let single = try ShortcutSupport.export(older, format: .pdf, singlePage: true)
        XCTAssertTrue(single.data.starts(with: Data("%PDF".utf8)))
        for format in ShortcutExportFormat.allCases {
            let file = try ShortcutSupport.export(newer, format: format.format, singlePage: false)
            XCTAssertFalse(file.data.isEmpty, "\(format)")
            XCTAssertEqual(file.filename, "Referat.\(format.format.fileExtension)")
        }
        let markdown = try ShortcutSupport.export(newer, format: .markdown, singlePage: false)
        XCTAssertTrue(String(decoding: markdown.data, as: UTF8.self).contains("Gliederung"))
    }

    @MainActor
    func testShortcutChangesAnOpenDocumentWithUndo() throws {
        let url = URL(fileURLWithPath: "/tmp/M9-offen-\(UUID().uuidString).mindmaps")
        let document = MindMapFile(data: Self.sample().data)
        let undo = UndoManager()
        undo.groupsByEvent = false
        OpenDocuments.register(document, url: url, undoManager: undo)
        defer { OpenDocuments.unregister(document) }

        XCTAssertTrue(OpenDocuments.find(url)?.document === document)
        let original = document.data
        undo.beginUndoGrouping()
        try MindMapCatalog.modify(url, actionName: "Knoten hinzufügen (Kurzbefehl)") { data in
            _ = try MindMapPackage.addNode("Neu per Siri", asTask: true, under: nil, to: &data)
        }
        undo.endUndoGrouping()
        XCTAssertEqual(document.data.root.children.last?.text, "Neu per Siri")
        XCTAssertEqual(undo.undoActionName, "Knoten hinzufügen (Kurzbefehl)")
        undo.undo()
        XCTAssertEqual(document.data, original)

        OpenDocuments.unregister(document)
        XCTAssertNil(OpenDocuments.find(url))
    }

    func testTutorialExplainsTheMacIntegration() throws {
        let package = try LearningSamples.load(language: "de")
        let tutorial = try XCTUnwrap(package.documents.first { $0.name.hasPrefix("Anleitung") })
        let texts = LibraryDocument.texts(of: tutorial.document.root).joined(separator: "\n")
        for word in ["Erinnerungen", "Spotlight", "Kurzbefehle"] {
            XCTAssertTrue(texts.contains(word), word)
        }
        XCTAssertTrue((6...8).contains(tutorial.document.root.children.count))
    }

    #endif
}
