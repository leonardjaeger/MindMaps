import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M2: Navigation, Zoom-Geometrie, Umhängen, Auswahl nach dem Löschen, Referenz-Dokument.
final class M2Tests: XCTestCase {

    private static func referenceLayout() -> (Node, MindMapLayout) {
        let root = CoreTests.referenceDocument().root
        let layout = TreeLayout.layout(root: root) { _, depth in
            CGSize(width: 80, height: depth == 0 ? 40 : 24)
        }
        return (root, layout)
    }

    // MARK: - Pfeiltasten

    func testArrowKeysFollowTheTree() {
        let (root, layout) = Self.referenceLayout()
        func go(_ id: UUID?, _ direction: MoveDirection) -> UUID? {
            MapNavigation.target(from: id, direction: direction, layout: layout, rootID: root.id)
        }
        let ast1 = root.children[0]            // rechts oben
        let ast3 = root.children[2]            // links oben

        XCTAssertEqual(go(nil, .down), root.id, "Ohne Auswahl landet man beim Hauptknoten")
        XCTAssertEqual(go(root.id, .right), ast1.id)
        XCTAssertEqual(go(root.id, .left), ast3.id)
        XCTAssertEqual(go(ast1.id, .right), ast1.children[1].id, "Nach außen: mittlerer Unterknoten")
        XCTAssertEqual(go(ast1.children[1].id, .left), ast1.id, "Nach innen: Elternknoten")
        XCTAssertEqual(go(ast3.id, .right), root.id, "Linke Seite: rechts führt zur Mitte")
        XCTAssertEqual(go(ast1.id, .down), root.children[1].id, "Runter: nächster Geschwisterknoten")
        XCTAssertEqual(go(ast1.children[0].id, .down), ast1.children[1].id)
        XCTAssertEqual(go(ast1.children[1].id, .up), ast1.children[0].id)
        XCTAssertEqual(go(ast1.children[2].id, .down), root.children[1].children[0].id,
                       "Letzter Geschwisterknoten: weiter zum nächsten Knoten darunter in derselben Spalte")
    }

    // MARK: - Zoom und Verschieben

    func testViewportRoundTripAndZoomAnchor() {
        let viewport = Viewport(zoom: 1.5, offset: CGPoint(x: 200, y: 120))
        let p = CGPoint(x: -37, y: 81)
        let back = viewport.toMap(viewport.toView(p))
        XCTAssertEqual(back.x, p.x, accuracy: 0.0001)
        XCTAssertEqual(back.y, p.y, accuracy: 0.0001)

        let anchor = CGPoint(x: 300, y: 250)
        let before = viewport.toMap(anchor)
        let zoomed = viewport.zoomed(by: 2, anchor: anchor)
        let after = zoomed.toMap(anchor)
        XCTAssertEqual(zoomed.zoom, 3, accuracy: 0.0001)
        XCTAssertEqual(after.x, before.x, accuracy: 0.0001, "Punkt unter dem Mauszeiger bleibt stehen")
        XCTAssertEqual(after.y, before.y, accuracy: 0.0001)
        XCTAssertEqual(viewport.zoomed(by: 100, anchor: anchor).zoom, Viewport.maxZoom)
        XCTAssertEqual(viewport.zoomed(by: 0.001, anchor: anchor).zoom, Viewport.minZoom)
    }

    func testFitToWindowShowsWholeMapCentered() {
        let (_, layout) = Self.referenceLayout()
        let size = CGSize(width: 500, height: 300)
        let fit = Viewport.fitting(layout.bounds, in: size, padding: 20, maxFitZoom: 2)
        let shown = fit.toView(layout.bounds)
        XCTAssertGreaterThanOrEqual(shown.minX, 19.99)
        XCTAssertGreaterThanOrEqual(shown.minY, 19.99)
        XCTAssertLessThanOrEqual(shown.maxX, 480.01)
        XCTAssertLessThanOrEqual(shown.maxY, 280.01)
        XCTAssertEqual(shown.midX, 250, accuracy: 0.01)
        XCTAssertEqual(shown.midY, 150, accuracy: 0.01)

        let small = CGRect(x: -50, y: -20, width: 100, height: 40)
        XCTAssertEqual(Viewport.fitting(small, in: size, maxFitZoom: 1).zoom, 1,
                       "Kleine Maps werden nicht aufgeblasen")
    }

    func testRevealMovesOnlyWhenNeeded() {
        let viewport = Viewport(zoom: 1, offset: CGPoint(x: 250, y: 150))
        let size = CGSize(width: 500, height: 300)
        let visible = CGRect(x: -20, y: -10, width: 40, height: 20)
        XCTAssertEqual(viewport.revealing(visible, in: size), viewport)

        let outside = CGRect(x: 400, y: 0, width: 60, height: 20)
        let moved = viewport.revealing(outside, in: size, margin: 24)
        XCTAssertEqual(moved.toView(outside).maxX, 500 - 24, accuracy: 0.0001)
        XCTAssertEqual(moved.offset.y, viewport.offset.y, "Senkrecht war nichts zu tun")
    }

    // MARK: - Umhängen und Löschen

    func testCanMoveRules() {
        let root = CoreTests.referenceDocument().root
        let ast1 = root.children[0], ast2 = root.children[1]
        XCTAssertFalse(root.canMove(root.id, toParent: ast1.id), "Hauptknoten bleibt fest")
        XCTAssertFalse(root.canMove(ast1.id, toParent: ast1.children[0].id), "Nicht in den eigenen Teilbaum")
        XCTAssertFalse(root.canMove(ast1.children[0].id, toParent: ast1.id), "Gleicher Elternknoten: keine Änderung")
        XCTAssertTrue(root.canMove(ast1.children[0].id, toParent: ast2.id))
        XCTAssertTrue(root.canMove(ast1.children[0].children[0].id, toParent: root.id))
    }

    func testSelectionAfterDeleting() {
        let root = CoreTests.referenceDocument().root
        let thema = root.children[0].children[0]
        XCTAssertEqual(root.selectionAfterRemoving(thema.children[0].id), thema.children[1].id, "Nächster")
        XCTAssertEqual(root.selectionAfterRemoving(thema.children[2].id), thema.children[1].id, "Voriger")
        XCTAssertNil(root.selectionAfterRemoving(root.id))

        var single = Node(text: "Wurzel")
        let only = Node(text: "Einziger")
        single.addChild(only, to: single.id)
        XCTAssertEqual(single.selectionAfterRemoving(only.id), single.id, "Einziges Kind: Elternknoten")
    }

    // MARK: - Referenz-Dokument (Docs/Referenz.mindmaps)

    func testReferenceDocumentLoads() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Docs/Referenz.mindmaps/document.json")
        let doc = try MindMapCodec.decode(Data(contentsOf: url))
        func depth(_ node: Node) -> Int { 1 + (node.children.map(depth).max() ?? 0) }
        XCTAssertGreaterThanOrEqual(doc.root.nodeCount, 50)
        XCTAssertEqual(depth(doc.root), 4, "4 Ebenen")
    }
}
