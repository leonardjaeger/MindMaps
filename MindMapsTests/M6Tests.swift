import XCTest
import AppKit
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M6: Notizen, Tags, Aufgaben, Suchen & Ersetzen, Lernbeispiele.
final class M6Tests: XCTestCase {

    // MARK: - Hilfen

    private func tasks(_ marks: [TaskMark?]) -> Node {
        Node(text: "Lernplan", children: marks.enumerated().map { Node(text: "Aufgabe \($0.offset + 1)", task: $0.element) })
    }

    private func shape(_ node: Node, _ depth: Int = 0) -> [String] {
        ["\(depth)|\(node.text)"] + node.children.flatMap { shape($0, depth + 1) }
    }

    // MARK: - Datenmodell

    func testNewFieldsAreSavedAndOldFilesStayReadable() throws {
        var doc = MindMapDocumentData.newDocument()
        doc.root.children = [Node(text: "A", note: "**fett** und [Link](https://example.org)",
                                  tags: ["Wichtig", "Prüfung"], task: .done)]
        let json = try MindMapCodec.encode(doc)
        XCTAssertEqual(try MindMapCodec.decode(json), doc)

        let plain = String(decoding: try MindMapCodec.encode(.newDocument()), as: UTF8.self)
        for key in ["\"note\"", "\"tags\"", "\"task\""] {
            XCTAssertFalse(plain.contains(key), "Leere Felder werden nicht gespeichert: \(key)")
        }
        let old = #"{"formatVersion":1,"root":{"id":"6B1F5C1E-6D2A-4C47-9A0E-4D2F0C1A7E11","text":"Alt"},"themeID":"blau"}"#
        let decoded = try MindMapCodec.decode(Data(old.utf8))
        XCTAssertEqual(decoded.root.note, "")
        XCTAssertEqual(decoded.root.tags, [])
        XCTAssertNil(decoded.root.task)
    }

    // MARK: - Aufgaben

    func testParentShowsPartialWhenTwoOfFourTasksAreDone() {
        var parent = tasks([.open, .open, .open, .open])
        XCTAssertEqual(parent.taskStatus, .open)
        parent.toggleDone(parent.children[0].id)
        parent.toggleDone(parent.children[1].id)
        XCTAssertEqual(parent.taskProgress.done, 2)
        XCTAssertEqual(parent.taskProgress.total, 4)
        XCTAssertEqual(parent.taskStatus, .partial, "M6-Abnahme: 2 von 4 → „teilweise“")
        XCTAssertNil(parent.task, "Der Elternknoten selbst wird dadurch keine Aufgabe")

        parent.toggleDone(parent.children[2].id)
        parent.toggleDone(parent.children[3].id)
        XCTAssertEqual(parent.taskStatus, .done)

        // Abhaken am Elternknoten wirkt auf alle Aufgaben darunter.
        parent.toggleDone(parent.id)
        XCTAssertEqual(parent.taskStatus, .open)
        XCTAssertTrue(parent.children.allSatisfy { $0.task == .open })
        parent.toggleDone(parent.id)
        XCTAssertTrue(parent.children.allSatisfy { $0.task == .done })
    }

    func testNestedTasksCountOnlyTheirLeaves() {
        var root = Node(text: "Projekt")
        var phase = Node(text: "Phase 1", task: .open)
        phase.children = [Node(text: "a", task: .done), Node(text: "b", task: .open)]
        root.children = [phase, Node(text: "Phase 2", task: .done), Node(text: "Notiz ohne Aufgabe")]
        XCTAssertEqual(root.taskProgress.done, 2)
        XCTAssertEqual(root.taskProgress.total, 3, "Phase 1 zählt über ihre zwei Unteraufgaben")
        XCTAssertEqual(root.children[0].taskStatus, .partial)
        XCTAssertNil(root.children[2].taskStatus)

        let open = root.openTasks()
        XCTAssertEqual(open.map(\.text), ["Phase 1", "b"])
        XCTAssertEqual(open.last?.path, ["Projekt", "Phase 1"])

        root.toggleTask(root.children[2].id)
        XCTAssertEqual(root.children[2].task, .open)
        root.toggleTask(root.children[2].id)
        XCTAssertNil(root.children[2].task)
    }

    // MARK: - Tags

    func testTagsCanBeToggledCountedAndRenamed() {
        var root = Node(text: "R", children: [Node(text: "a"), Node(text: "b")])
        root.toggleTag("Wichtig", on: root.children[0].id)
        root.toggleTag("Wichtig", on: root.children[1].id)
        root.toggleTag("Prüfung", on: root.children[1].id)
        XCTAssertEqual(root.tagCounts, ["Wichtig": 2, "Prüfung": 1])
        root.toggleTag("Wichtig", on: root.children[0].id)
        XCTAssertEqual(root.tagCounts["Wichtig"], 1)
        root.renameTag("Prüfung", to: "Klausur")
        XCTAssertEqual(root.children[1].tags, ["Wichtig", "Klausur"])
        XCTAssertEqual(root.ids { $0.tags.contains("Klausur") }, [root.children[1].id])
    }

    func testTagCatalogColorsAreStable() {
        let catalog = TagCatalog.standard
        XCTAssertEqual(catalog.tags.count, 7, "⌥ ⌘ 1 … 7")
        XCTAssertEqual(catalog.hex(for: "Wichtig"), TagCatalog.colors[0].hex)
        XCTAssertEqual(catalog.hex(for: "Eigenes Tag"), catalog.hex(for: "Eigenes Tag"))
        XCTAssertEqual(catalog.ordered(including: ["Zebra", "Apfel", "Wichtig"]).suffix(2), ["Apfel", "Zebra"])
        var copy = catalog
        XCTAssertTrue(copy.add("Seminar"))
        XCTAssertFalse(copy.add("Seminar"))
        XCTAssertFalse(copy.add("   "))
    }

    // MARK: - Notizen

    func testNoteMarkupRoundTrip() {
        let markdown = """
        Das ist **fett**, *kursiv* und ***beides***.
        Siehe [PH Freiburg](https://www.ph-freiburg.de) und [**fetter Link**](https://example.org/a_b).
        - erster Punkt
        - zweiter Punkt
        1. erstens
        2. zweitens

        Sonderzeichen \\* \\_ \\[ \\] bleiben stehen.
        \\- kein Listenpunkt
        """
        let paragraphs = NoteMarkup.parse(markdown)
        XCTAssertEqual(paragraphs[0].spans.map(\.text), ["Das ist ", "fett", ", ", "kursiv", " und ", "beides", "."])
        XCTAssertTrue(paragraphs[0].spans[1].bold)
        XCTAssertTrue(paragraphs[0].spans[3].italic)
        XCTAssertEqual(paragraphs[1].spans[1].link, "https://www.ph-freiburg.de")
        XCTAssertEqual(paragraphs[2].kind, .bullet)
        XCTAssertEqual(paragraphs[5].kind, .numbered(2))
        XCTAssertEqual(paragraphs[8].kind, .plain)
        XCTAssertEqual(NoteMarkup.markdown(paragraphs), markdown)
        XCTAssertEqual(NoteMarkup.plainText("**a** [b](https://x.de)\n- c"), "a b\n• c")
    }

    /// M6-Abnahme: Fett, Liste und Link überstehen das Textfeld und das Speichern.
    @MainActor
    func testFormattedNoteSurvivesTextFieldAndSaving() throws {
        let markdown = "Ein **wichtiger** Satz mit [Link](https://example.org).\n- Punkt eins\n- Punkt *zwei*\n1. Schritt"
        let attributed = NoteText.attributedString(fromMarkdown: markdown)
        XCTAssertTrue(attributed.string.contains("•\tPunkt eins"))
        XCTAssertEqual(NoteText.markdown(from: attributed), markdown)

        var doc = MindMapDocumentData.newDocument()
        doc.root.note = NoteText.markdown(from: attributed)
        let reloaded = try MindMapCodec.decode(try MindMapCodec.encode(doc))
        XCTAssertEqual(NoteText.markdown(from: NoteText.attributedString(fromMarkdown: reloaded.root.note)), markdown)
    }

    // MARK: - Suchen und Ersetzen

    func testFindAndReplaceInTextsAndNotes() {
        var root = Node(text: "Zellatmung", children: [
            Node(text: "Glykolyse", note: "Läuft im Cytoplasma ab."),
            Node(text: "Cytoplasma und Mitochondrium"),
            Node(text: "Atmungskette"),
        ])
        var options = FindOptions()
        XCTAssertEqual(root.findMatches("cytoplasma", options: options).map(\.id),
                       [root.children[0].id, root.children[1].id])
        XCTAssertTrue(root.findMatches("cytoplasma", options: options)[0].inNote)
        options.includeNotes = false
        XCTAssertEqual(root.findMatches("cytoplasma", options: options).count, 1)
        options.caseSensitive = true
        XCTAssertEqual(root.findMatches("cytoplasma", options: options).count, 0)

        let all = FindOptions()
        XCTAssertEqual(root.replace(in: root.children[1].id, "Cytoplasma", with: "Zytoplasma", options: all), 1)
        XCTAssertEqual(root.children[1].text, "Zytoplasma und Mitochondrium")
        XCTAssertEqual(root.children[0].note, "Läuft im Cytoplasma ab.", "Nur der gewählte Knoten")
    }

    func testReplaceAllCountsEveryOccurrence() {
        var root = Node(text: "aaa", children: [Node(text: "b", note: "a a")])
        XCTAssertEqual(root.replaceAll("a", with: "aa", options: FindOptions()), 5, "Ersetztes wird nicht nochmal ersetzt")
        XCTAssertEqual(root.text, "aaaaaa")
        XCTAssertEqual(root.children[0].note, "aa aa")
        XCTAssertEqual(root.replaceAll("", with: "x", options: FindOptions()), 0)
    }

    // MARK: - Rückgängig

    func testNoteTagAndTaskChangesAreUndoable() {
        var start = MindMapDocumentData.newDocument()
        start.root.children = [Node(text: "A")]
        let document = MindMapFile(data: start)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)
        let id = start.root.children[0].id
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping(); body(); undo.endUndoGrouping()
        }
        step { actions.setNote("**Notiz**", of: id) }
        step { actions.toggleTag("Wichtig", on: id) }
        step { actions.toggleDone(id) }
        step { actions.replaceAll("A", with: "B", options: FindOptions()) }
        let node = document.data.root.children[0]
        XCTAssertEqual(node.note, "**Notiz**")
        XCTAssertEqual(node.tags, ["Wichtig"])
        XCTAssertEqual(node.task, .done)
        XCTAssertEqual(node.text, "B")

        var count = 0
        while undo.canUndo { undo.undo(); count += 1 }
        XCTAssertEqual(count, 4)
        XCTAssertEqual(document.data, start)
    }

    // MARK: - Export behält Aufgaben und Notizen

    func testMarkdownAndOPMLKeepTasksAndNotes() throws {
        var root = Node(text: "Thema", note: "Leitfrage mit **fett**")
        var plan = Node(text: "Lernplan", note: "Zeile 1\n\nZeile 3")
        plan.children = [Node(text: "Lesen", task: .done), Node(text: "Üben", note: "- Aufgabe 1\n- Aufgabe 2", task: .open)]
        root.children = [plan]

        for back in [try MarkdownFormat.parse(MarkdownFormat.export(root), fallbackTitle: "x"),
                     try OPMLFormat.parse(Data(OPMLFormat.export(root).utf8), fallbackTitle: "x")] {
            XCTAssertEqual(shape(back), shape(root))
            XCTAssertEqual(back.note, root.note)
            XCTAssertEqual(back.children[0].note, plan.note)
            XCTAssertEqual(back.children[0].children.map(\.task), [.done, .open])
            XCTAssertEqual(back.children[0].children[1].note, "- Aufgabe 1\n- Aufgabe 2")
        }
    }

    // MARK: - Darstellung

    @MainActor
    func testNodeMakesRoomForCheckboxNoteAndTags() throws {
        let metrics = NodeMetrics(theme: ThemeStore.theme(withID: "blau"))
        let plain = Node(text: "Glykolyse")
        let decorated = Node(text: "Glykolyse", note: "x", tags: ["Wichtig", "Prüfung"], task: .open)
        let small = metrics.size(of: plain, depth: 2)
        let big = metrics.size(of: decorated, depth: 2)
        XCTAssertGreaterThan(big.width, small.width)
        XCTAssertGreaterThan(big.height, small.height)

        let frame = CGRect(origin: CGPoint(x: 100, y: 50), size: big)
        let layout = metrics.contentLayout(of: decorated, depth: 2, frame: frame)
        let box = try XCTUnwrap(layout.leadingRect)
        let note = try XCTUnwrap(layout.noteRect)
        for rect in [box, note, layout.textRect] + layout.tagRects.map(\.rect) {
            XCTAssertTrue(frame.contains(rect), "\(rect) liegt im Knoten")
        }
        XCTAssertFalse(box.intersects(layout.textRect))
        XCTAssertFalse(note.intersects(layout.textRect))
        XCTAssertEqual(layout.tagRects.map(\.tag), ["Wichtig", "Prüfung"])
    }

    // MARK: - Lernbeispiele

    func testLearningSamplesFollowTheLearningStructure() throws {
        let package = try LearningSamples.load(language: "de")
        let names = package.documents.map(\.name)
        XCTAssertEqual(names.count, 7)
        for subject in ["Anleitung", "Biologie", "Jura", "Medizin", "Informatik", "Geschichte", "Politik"] {
            XCTAssertTrue(names.contains { $0.contains(subject) }, "\(subject) fehlt")
        }
        let allowed = Set(TagCatalog.standard.tags.map(\.name))
        for entry in package.documents {
            let root = entry.document.root
            XCTAssertFalse(root.note.isEmpty, "\(entry.name): Leitfrage in der Notiz")
            XCTAssertTrue((6...8).contains(root.children.count), "\(entry.name): 6–8 Hauptäste")
            XCTAssertTrue(ThemeStore.catalog.themes.contains { $0.id == entry.document.themeID })
            XCTAssertTrue(Set(root.tagCounts.keys).isSubset(of: allowed), "\(entry.name): nur Standard-Tags")
            XCTAssertNotNil(root.children.first { $0.text == "Lernplan" || $0.text.contains("Aufgaben") }?.taskStatus,
                            "\(entry.name): Lernplan mit Aufgaben")
            guard !entry.name.hasPrefix("Anleitung") else { continue }
            let test = try XCTUnwrap(root.children.first { $0.text == "Selbsttest" }, entry.name)
            XCTAssertTrue(test.isCollapsed, "\(entry.name): Selbsttest ist eingeklappt")
            XCTAssertGreaterThanOrEqual(test.children.count, 3)
            XCTAssertTrue(test.children.allSatisfy { $0.tags.contains("Frage") })
            XCTAssertGreaterThanOrEqual(test.children.filter { !$0.note.isEmpty }.count, 3, "Antworten in den Notizen")
            XCTAssertNotNil(root.children.first { $0.text == "Grundbegriffe" }, entry.name)
            XCTAssertEqual(root.children.first { $0.text == "Lernplan" }?.taskStatus, .partial, entry.name)
        }
    }

    func testLearningSamplesAreCreatedInTheLibrary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapsM6-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MindMapsM6-\(UUID().uuidString)"))

        LearningSamples.installIfNeeded(in: root, defaults: defaults)
        LearningSamples.installIfNeeded(in: root, defaults: defaults)
        var cache: [URL: LibraryDocument] = [:]
        let contents = LibraryScanner.scan(root, cache: &cache)
        XCTAssertEqual(contents.documents.count, 7, "Nur einmal angelegt")
        XCTAssertEqual(contents.root.children?.map(\.name), ["Lernbeispiele"])

        // M6-Abnahme: Die Aufgabenübersicht findet offene Aufgaben aus mindestens 3 Dokumenten.
        let withTasks = contents.documents.filter { !$0.data.root.openTasks().isEmpty }
        XCTAssertGreaterThanOrEqual(withTasks.count, 3)
    }
}
