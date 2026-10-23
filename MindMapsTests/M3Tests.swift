import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M3: Ebene ändern (Tab / ⇧ Tab), Umsortieren in der Outline, Einklappen.
final class M3Tests: XCTestCase {

    // MARK: - Tab / ⇧ Tab

    func testIndentMakesNodeLastChildOfPreviousSibling() {
        var root = CoreTests.referenceDocument().root
        let ast1 = root.children[0], ast2 = root.children[1]
        root.updateNode(id: ast1.id) { $0.isCollapsed = true }

        XCTAssertTrue(root.indentNode(ast2.id))
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(root.node(withID: ast1.id)?.children.last?.id, ast2.id)
        XCTAssertEqual(root.node(withID: ast1.id)?.isCollapsed, false, "Ziel wird aufgeklappt, damit der Knoten sichtbar bleibt")
        XCTAssertEqual(root.nodeCount, 53)

        XCTAssertFalse(root.indentNode(root.children[0].id), "Erstes Kind hat keinen vorigen Geschwisterknoten")
        XCTAssertFalse(root.indentNode(root.id), "Hauptknoten bleibt")
    }

    func testOutdentPlacesNodeRightAfterItsParent() {
        var root = CoreTests.referenceDocument().root
        let ast1 = root.children[0]
        let thema = ast1.children[1]

        XCTAssertTrue(root.outdentNode(thema.id))
        XCTAssertEqual(Array(root.children.map(\.id).prefix(2)), [ast1.id, thema.id])
        XCTAssertEqual(root.node(withID: ast1.id)?.children.count, 2)
        XCTAssertEqual(root.node(withID: thema.id)?.children.count, 3, "Unterknoten wandern mit")
        XCTAssertEqual(root.nodeCount, 53)

        XCTAssertFalse(root.outdentNode(root.children[0].id), "Äste des Hauptknotens können nicht höher")
    }

    func testIndentThenOutdentRestoresLevel() {
        var root = CoreTests.referenceDocument().root
        let original = root
        let thema = root.children[0].children[1]
        XCTAssertTrue(root.indentNode(thema.id))
        XCTAssertEqual(root.parentID(of: thema.id), original.children[0].children[0].id)
        XCTAssertTrue(root.outdentNode(thema.id))
        XCTAssertEqual(root, original, "Tab und danach ⇧ Tab ergibt wieder den Ausgangszustand")
    }

    // MARK: - Umsortieren (Drag & Drop in der Outline)

    func testMoveBesideReordersAndChangesParent() {
        var root = CoreTests.referenceDocument().root
        let ast1 = root.children[0], ast3 = root.children[2]
        let punkt = ast1.children[0].children[2]

        XCTAssertTrue(root.moveNode(ast3.id, beside: ast1.id, after: false))
        XCTAssertEqual(root.children.first?.id, ast3.id, "Vor Ast 1 einsortiert")

        XCTAssertTrue(root.moveNode(punkt.id, beside: ast3.children[0].id, after: true))
        XCTAssertEqual(root.parentID(of: punkt.id), ast3.id, "Neuer Elternknoten")
        XCTAssertEqual(root.node(withID: ast3.id)?.children.map(\.id)[1], punkt.id, "Direkt nach dem Ziel")
        XCTAssertEqual(root.nodeCount, 53)
    }

    func testMoveBesideRules() {
        let root = CoreTests.referenceDocument().root
        let ast1 = root.children[0]
        XCTAssertFalse(root.canMove(ast1.id, beside: root.id), "Neben den Hauptknoten geht nicht")
        XCTAssertFalse(root.canMove(root.id, beside: ast1.id), "Hauptknoten bleibt")
        XCTAssertFalse(root.canMove(ast1.id, beside: ast1.children[0].id), "Nicht in den eigenen Teilbaum")
        XCTAssertFalse(root.canMove(ast1.id, beside: ast1.id))
        XCTAssertTrue(root.canMove(ast1.children[0].id, beside: ast1.children[2].id), "Umsortieren unter Geschwistern")
    }

    // MARK: - Einklappen

    func testCollapseRulesAndVisibleNode() {
        var root = CoreTests.referenceDocument().root
        let ast1 = root.children[0]
        let thema = ast1.children[0]
        let punkt = thema.children[0]

        XCTAssertFalse(root.canToggleCollapse(root.id), "Hauptknoten wird nicht eingeklappt")
        XCTAssertFalse(root.canToggleCollapse(punkt.id), "Ohne Unterknoten nichts einzuklappen")
        XCTAssertTrue(root.canToggleCollapse(thema.id))

        XCTAssertEqual(root.visibleNode(for: punkt.id), punkt.id)
        root.updateNode(id: thema.id) { $0.isCollapsed = true }
        XCTAssertEqual(root.visibleNode(for: punkt.id), thema.id)
        root.updateNode(id: ast1.id) { $0.isCollapsed = true }
        XCTAssertEqual(root.visibleNode(for: punkt.id), ast1.id, "Der oberste eingeklappte Vorfahr ist zu sehen")
        XCTAssertNil(root.visibleNode(for: UUID()))
    }

    func testCollapsedStateSurvivesSaving() throws {
        var doc = CoreTests.referenceDocument()
        let thema = doc.root.children[1].children[2]
        doc.root.updateNode(id: thema.id) { $0.isCollapsed = true }
        let loaded = try MindMapCodec.decode(try MindMapCodec.encode(doc))
        XCTAssertEqual(loaded.root.node(withID: thema.id)?.isCollapsed, true)
        XCTAssertEqual(loaded.root.visibleRows().count, 53 - 3)
    }
}
