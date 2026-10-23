import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für 1.3: Knoten aus MintMarkPDF anlegen (`mindmaps://add?…`) und Links per Ziehen (M30 der PDF-App).
final class M13Tests: XCTestCase {

    // MARK: - Hilfen

    private static let mapPath = "/Users/leonard/Dokumente/MindMaps/Ünï Ordner/Referat & Co.mindmaps"
    private static let passage = "mintmarkpdf://open?v=1&file=%2FUsers%2Fleonard%2FLiteratur%2FA.pdf&page=11&label=12"

    /// Kodiert wie MintMarkPDF: nur A–Z, a–z, 0–9 und „-._~“ bleiben stehen.
    private static func encode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static func addLink(_ items: [(String, String)], prefix: String = "mindmaps://add?") -> String {
        prefix + items.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
    }

    /// Gültiger Link mit Titel und Pfad, dazu weitere Werte.
    private static func link(title: String = "Kernaussage", file: String = M13Tests.mapPath,
                             _ more: [(String, String)] = []) -> String {
        addLink([("v", "1"), ("file", file), ("title", title)] + more)
    }

    // MARK: - Lesen

    func testRoundTripWithSpecialCharacters() throws {
        let parent = UUID()
        let title = "Über „Lernen“ & Lehren = 100 % #1 + mehr 🙂 👨‍👩‍👧"
        let note = "„Zitat mit & und = und #“ (Autor, 2020, S. 12)\n\nEigene Notiz + 50 % \\*kein Fett\\*"
        let link = Self.addLink([("v", "1"), ("file", Self.mapPath), ("parent", parent.uuidString),
                                 ("title", title), ("note", note), ("link", Self.passage)])
        let request = try XCTUnwrap(ExternalNodeRequest.parse(link))
        XCTAssertEqual(request.file.path, Self.mapPath)
        XCTAssertEqual(request.parent, parent)
        XCTAssertEqual(request.title, title)
        XCTAssertEqual(request.note, note)
        XCTAssertEqual(request.link, Self.passage)
    }

    func testSchemeAndHostIgnoreCaseAndMissingVersionMeansOne() throws {
        let upper = Self.addLink([("file", Self.mapPath), ("title", "Ohne Fassung")], prefix: "MindMaps://ADD?")
        let request = try XCTUnwrap(ExternalNodeRequest.parse(upper))
        XCTAssertEqual(request.title, "Ohne Fassung")
        XCTAssertNil(request.parent)
        XCTAssertNil(request.note)
        XCTAssertNil(request.link)
        // Unbekannte Werte werden übergangen, Leerraum um den Link herum auch.
        XCTAssertNotNil(ExternalNodeRequest.parse("  " + Self.link([("farbe", "rot")]) + "\n"))
    }

    func testNewerVersionsAreRejected() {
        XCTAssertNotNil(ExternalNodeRequest.parse(Self.addLink([("v", "1"), ("file", Self.mapPath), ("title", "A")])))
        XCTAssertNil(ExternalNodeRequest.parse(Self.addLink([("v", "2"), ("file", Self.mapPath), ("title", "A")])))
        XCTAssertNil(ExternalNodeRequest.parse(Self.addLink([("v", "x"), ("file", Self.mapPath), ("title", "A")])))
        XCTAssertNil(ExternalNodeRequest.parse(Self.addLink([("v", "0"), ("file", Self.mapPath), ("title", "A")])))
    }

    func testFileAndTitleAreRequired() {
        XCTAssertNil(ExternalNodeRequest.parse(Self.addLink([("v", "1"), ("file", Self.mapPath)])), "ohne Titel")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(title: "  \t\u{0007}  ")), "Titel nach dem Säubern leer")
        XCTAssertNil(ExternalNodeRequest.parse(Self.addLink([("v", "1"), ("title", "A")])), "ohne Datei")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(file: "Dokumente/Referat.mindmaps")), "relativer Pfad")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(file: "~/Referat.mindmaps")), "relativer Pfad")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(file: "/Users/leonard/Literatur/A.pdf")), "falsche Endung")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(file: "/Users/leonard/Referat")), "ohne Endung")
        XCTAssertNotNil(ExternalNodeRequest.parse(Self.link(file: "/Users/leonard/Referat.MINDMAPS")))
        let longPath = "/" + String(repeating: "a", count: 4_100) + ".mindmaps"
        XCTAssertNil(ExternalNodeRequest.parse(Self.link(file: longPath)), "Pfad über 4.096 Zeichen")
        XCTAssertNil(ExternalNodeRequest.parse("mindmaps://open?" + "file=\(Self.encode(Self.mapPath))&title=A"))
        XCTAssertNil(ExternalNodeRequest.parse("https://add?file=\(Self.encode(Self.mapPath))&title=A"))
    }

    func testInvalidParentFallsBackToRoot() throws {
        let invalid = try XCTUnwrap(ExternalNodeRequest.parse(Self.link([("parent", "kein-knoten")])))
        XCTAssertNil(invalid.parent)
        let id = UUID()
        XCTAssertEqual(ExternalNodeRequest.parse(Self.link([("parent", id.uuidString.lowercased())]))?.parent, id)
    }

    func testLimits() throws {
        let longTitle = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(title: String(repeating: "Wort ", count: 80))))
        XCTAssertLessThanOrEqual(longTitle.title.count, 200)
        XCTAssertTrue(longTitle.title.hasSuffix("…"))
        XCTAssertEqual(ExternalNodeRequest.parse(Self.link(title: String(repeating: "x", count: 200)))?.title.count, 200)

        let longNote = try XCTUnwrap(ExternalNodeRequest.parse(Self.link([("note", String(repeating: "Notiz ", count: 500))])))
        XCTAssertLessThanOrEqual(longNote.note?.count ?? 0, 2_000)
        XCTAssertTrue(longNote.note?.hasSuffix("…") ?? false)

        let base = "https://example.org/"
        let fits = base + String(repeating: "a", count: 4_000 - base.count)
        XCTAssertEqual(ExternalNodeRequest.parse(Self.link([("link", fits)]))?.link, fits)
        let tooLong = fits + "a"
        let withoutLink = try XCTUnwrap(ExternalNodeRequest.parse(Self.link([("link", tooLong)])))
        XCTAssertNil(withoutLink.link, "Link über 4.000 Zeichen fällt weg, der Rest bleibt")

        let huge = Self.link([("note", String(repeating: "a", count: 16_000))])
        XCTAssertGreaterThan(huge.count, 16_000)
        XCTAssertNil(ExternalNodeRequest.parse(huge), "ganzer Link über 16.000 Zeichen")
    }

    func testOnlyAllowedLinkSchemesAreKept() {
        func link(_ value: String) -> String? { ExternalNodeRequest.parse(Self.link([("link", value)]))?.link }
        XCTAssertEqual(link(Self.passage), Self.passage)
        XCTAssertEqual(link("https://www.ph-freiburg.de/"), "https://www.ph-freiburg.de/")
        XCTAssertEqual(link("HTTP://example.org"), "HTTP://example.org")
        XCTAssertEqual(link("mailto:leonard@example.org"), "mailto:leonard@example.org")
        let open = DocumentLink.make(file: URL(fileURLWithPath: "/Users/leonard/Referat.mindmaps"), node: UUID())
        XCTAssertEqual(link(open), open)
        XCTAssertNil(link("javascript:alert(1)"))
        XCTAssertNil(link("file:///etc/passwd"))
        XCTAssertNil(link("ftp://example.org"))
        XCTAssertNil(link("www.ph-freiburg.de"), "ohne Schema")
        XCTAssertNil(link(Self.link()), "kein Anlegen-Link als Link am Knoten")
        XCTAssertNotNil(ExternalNodeRequest.parse(Self.link([("link", "javascript:alert(1)")])), "nur der Link fällt weg")
    }

    func testTitleIsCleaned() {
        func title(_ value: String) -> String? { ExternalNodeRequest.parse(Self.link(title: value))?.title }
        XCTAssertEqual(title("Zeile 1\nZeile 2\r\nZeile 3\tTab\u{2028}Absatz\u{2029}Ende"),
                       "Zeile 1 Zeile 2 Zeile 3 Tab Absatz Ende")
        XCTAssertEqual(title("   viele    Leerzeichen \u{00A0}\u{00A0} hier  "), "viele Leerzeichen hier")
        XCTAssertEqual(title("\u{0007}Glo\u{200B}cke\u{202E}!"), "Glocke!", "Steuer- und Formatzeichen")
        XCTAssertEqual(title("Familie 👨‍👩‍👧"), "Familie 👨‍👩‍👧", "Verbinder in Emojis bleibt")
        XCTAssertEqual(ExternalNodeRequest.cleanedTitle("A\u{FEFF}B\u{00AD}C\u{0000}D"), "ABCD")
    }

    func testNoteKeepsLineBreaks() {
        let raw = "  Zeile 1\r\nZeile 2\n\n  Absatz   mit\tLücken \u{0007}\u{2028}Neue Zeile\n\n"
        XCTAssertEqual(ExternalNodeRequest.parse(Self.link([("note", raw)]))?.note,
                       "Zeile 1\nZeile 2\n\nAbsatz mit Lücken\nNeue Zeile")
        XCTAssertNil(ExternalNodeRequest.parse(Self.link([("note", " \n\u{0007}\n ")]))?.note, "leer = keine Notiz")
    }

    /// `DocumentLink.parse` hält einen Anlegen-Link nicht für einen Öffnen-Link – und umgekehrt.
    func testAddLinksAreNotOpenLinks() {
        let add = Self.link()
        XCTAssertTrue(ExternalNodeRequest.isAddLink(add))
        XCTAssertTrue(ExternalNodeRequest.isAddLink("  MINDMAPS://Add?file=%2Fa.mindmaps&title=A "))
        XCTAssertNil(DocumentLink.parse(add), "add-Link mit file= ist kein Öffnen-Link")
        XCTAssertFalse(DocumentLink.isDocumentLink(add))

        let open = DocumentLink.make(file: URL(fileURLWithPath: "/Users/leonard/Referat.mindmaps"), node: UUID())
        XCTAssertFalse(ExternalNodeRequest.isAddLink(open))
        XCTAssertNotNil(DocumentLink.parse(open))
        XCTAssertNil(ExternalNodeRequest.parse(open))
        XCTAssertFalse(ExternalNodeRequest.isAddLink("mindmaps://open?file=%2FUsers%2Fadd.mindmaps"))
        XCTAssertFalse(ExternalNodeRequest.isAddLink("https://add.example.org/?file=a.mindmaps"))
        XCTAssertFalse(ExternalNodeRequest.isAddLink(Self.passage))
    }

    // MARK: - Links per Ziehen

    func testDroppedLinksAreFiltered() {
        XCTAssertEqual(ExternalNodeRequest.acceptedLink("  https://www.ph-freiburg.de/  \n"), "https://www.ph-freiburg.de/")
        XCTAssertEqual(ExternalNodeRequest.acceptedLink(Self.passage), Self.passage)
        XCTAssertEqual(ExternalNodeRequest.acceptedLink("mailto:leonard@example.org"), "mailto:leonard@example.org")
        XCTAssertEqual(ExternalNodeRequest.acceptedLink("MINDMAPS://open?file=%2Fa.mindmaps"), "MINDMAPS://open?file=%2Fa.mindmaps")

        XCTAssertNil(ExternalNodeRequest.acceptedLink(""))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("Zwei\nhttps://example.org"), "mehrzeilig")
        XCTAssertNil(ExternalNodeRequest.acceptedLink("Siehe https://example.org"), "Satz mit Link")
        XCTAssertNil(ExternalNodeRequest.acceptedLink("javascript:alert(1)"))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("file:///Users/leonard/A.pdf"))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("https://"))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("mailto:"))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("Kernaussage"))
        XCTAssertNil(ExternalNodeRequest.acceptedLink("https://example.org/" + String(repeating: "a", count: 4_000)))
        XCTAssertNil(ExternalNodeRequest.acceptedLink(Self.link()), "Anlegen-Links werden beim Ziehen abgelehnt")
        XCTAssertNil(ExternalNodeRequest.acceptedLink(UUID().uuidString), "Zeile aus der Outline")
    }

    func testPassageLinksAreRecognized() {
        XCTAssertTrue(ExternalNodeRequest.isPassageLink(Self.passage))
        XCTAssertTrue(ExternalNodeRequest.isPassageLink("MintMarkPDF://open?v=1"))
        XCTAssertFalse(ExternalNodeRequest.isPassageLink("https://example.org"))
        XCTAssertFalse(ExternalNodeRequest.isPassageLink(""))
    }

    // MARK: - Anlegen im Dokument

    func testInsertIntoDataExpandsTheWayToTheNewNode() throws {
        var data = CoreTests.referenceDocument()
        let branch = data.root.children[2]
        let parent = branch.children[1]
        data.root.updateNode(id: branch.id) { $0.isCollapsed = true }
        data.root.updateNode(id: parent.id) { $0.isCollapsed = true }

        let request = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(title: "Neu", [("parent", parent.id.uuidString)])))
        let placement = request.insert(into: &data)
        XCTAssertFalse(placement.parentMissing)
        XCTAssertEqual(data.root.node(withID: parent.id)?.children.last?.id, placement.nodeID)
        XCTAssertEqual(data.root.visibleNode(for: placement.nodeID), placement.nodeID, "Weg aufgeklappt")
    }

    #if canImport(AppKit)
    @MainActor
    func testNodeIsAddedUnderParentAsOneUndoStep() throws {
        let document = MindMapFile(data: CoreTests.referenceDocument())
        let original = document.data
        let parent = original.root.children[1].children[0].id
        let undo = UndoManager()
        undo.groupsByEvent = false

        let request = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(
            title: "Lernen ist aktiv", [("parent", parent.uuidString), ("note", "„Zitat“ (Autor, 2020, S. 12)"),
                                        ("link", Self.passage)])))
        undo.beginUndoGrouping()
        let placement = ExternalNodeAdder.insert(request, into: document, undoManager: undo,
                                                 actionName: "Knoten aus MintMarkPDF")
        undo.endUndoGrouping()
        XCTAssertFalse(placement.parentMissing)

        let node = try XCTUnwrap(document.data.root.node(withID: placement.nodeID))
        XCTAssertEqual(document.data.root.node(withID: parent)?.children.last?.id, node.id)
        XCTAssertEqual(node.text, "Lernen ist aktiv")
        XCTAssertEqual(node.note, "„Zitat“ (Autor, 2020, S. 12)")
        XCTAssertEqual(node.link, Self.passage)
        XCTAssertEqual(document.data.root.nodeCount, original.root.nodeCount + 1)
        XCTAssertEqual(undo.undoActionName, "Knoten aus MintMarkPDF")
        let after = document.data

        undo.undo()
        XCTAssertEqual(document.data, original, "ein Rückgängig entfernt genau diesen Knoten")
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(document.data, after, "Wiederholen stellt ihn wieder her (gleiche ID)")
    }

    @MainActor
    func testUnknownParentFallsBackToTheRoot() throws {
        let document = MindMapFile(data: CoreTests.referenceDocument())
        let missing = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(title: "Waise", [("parent", UUID().uuidString)])))
        let placement = ExternalNodeAdder.insert(missing, into: document, undoManager: nil)
        XCTAssertTrue(placement.parentMissing)
        XCTAssertEqual(document.data.root.children.last?.id, placement.nodeID)

        let withoutParent = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(title: "Ohne Eltern")))
        let second = ExternalNodeAdder.insert(withoutParent, into: document, undoManager: nil)
        XCTAssertFalse(second.parentMissing, "kein Elternknoten angegeben: kein Hinweis nötig")
        XCTAssertEqual(document.data.root.children.last?.id, second.nodeID)
    }

    /// „Rückgängig“ im Hinweis nur, solange der oberste Schritt das Anlegen ist.
    @MainActor
    func testBannerUndoOnlyWhileTheInsertIsOnTop() throws {
        let document = MindMapFile(data: CoreTests.referenceDocument())
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        let request = try XCTUnwrap(ExternalNodeRequest.parse(Self.link(title: "Neu")))
        var placement: ExternalNodeRequest.Placement?
        step { placement = ExternalNodeAdder.insert(request, into: document, undoManager: undo) }
        let nodeID = try XCTUnwrap(placement).nodeID
        let notice = ExternalNodeNotices.Notice(nodeID: nodeID, message: "",
                                                stateAfter: document.data, actionName: "Knoten aus MintMarkPDF")
        XCTAssertTrue(ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: undo))

        step { actions.setText("Später geändert", of: document.data.root.id) }
        XCTAssertFalse(ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: undo))
        undo.undo()
        XCTAssertTrue(ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: undo),
                      "nach Rückgängig der späteren Änderung wieder oben")
        undo.undo()
        XCTAssertFalse(ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: undo))
        XCTAssertFalse(ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: nil))
    }

    func testNoticesAreKeptPerDocument() {
        let store = ExternalNodeNotices()
        let a = URL(fileURLWithPath: "/tmp/A.mindmaps")
        let notice = ExternalNodeNotices.Notice(nodeID: UUID(), message: "Knoten angelegt",
                                                stateAfter: .newDocument(), actionName: "Knoten aus MintMarkPDF")
        store.post(notice, for: a)
        XCTAssertEqual(store.notice(for: URL(fileURLWithPath: "/tmp/A.mindmaps/")), notice, "mit „/“ am Ende")
        XCTAssertNil(store.notice(for: URL(fileURLWithPath: "/tmp/B.mindmaps")))
        store.dismiss(UUID(), for: a)
        XCTAssertNotNil(store.notice(for: a), "anderer Hinweis bleibt")
        store.dismiss(notice.id, for: a)
        XCTAssertNil(store.notice(for: a))
    }
    #endif
}
