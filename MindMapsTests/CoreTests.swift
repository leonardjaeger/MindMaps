import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für Datenmodell, Speichern/Laden, Baum-Operationen, Themes und Layout.
final class CoreTests: XCTestCase {

    // MARK: - Hilfen

    /// Referenz-Dokument: 1 + 4 + 4×3 + 4×3×3 = 53 Knoten in 4 Ebenen.
    static func referenceDocument() -> MindMapDocumentData {
        var root = Node(text: "Referenz")
        for a in 1...4 {
            var branch = Node(text: "Ast \(a)")
            for b in 1...3 {
                var sub = Node(text: "Thema \(a).\(b)")
                for c in 1...3 { sub.children.append(Node(text: "Punkt \(a).\(b).\(c)")) }
                branch.children.append(sub)
            }
            root.children.append(branch)
        }
        return MindMapDocumentData(root: root, themeID: "ozean")
    }

    // MARK: - M1: Speichern und Laden

    func testNewDocumentHasOneRootNode() {
        let doc = MindMapDocumentData.newDocument()
        XCTAssertEqual(doc.root.nodeCount, 1)
        XCTAssertEqual(doc.root.text, "Zentrales Thema")
        XCTAssertEqual(doc.formatVersion, MindMapDocumentData.currentFormatVersion)
        XCTAssertEqual(doc.themeID, "blau")
    }

    func testSaveAndLoadRoundTripIsIdentical() throws {
        var doc = Self.referenceDocument()
        doc.root.updateNode(id: doc.root.children[1].id) { $0.isCollapsed = true }
        doc.root.children[0].text = "Umlaute äöüß & Emoji 🧠 / \"Zitat\""
        let data = try MindMapCodec.encode(doc)
        let loaded = try MindMapCodec.decode(data)
        XCTAssertEqual(loaded, doc)
        XCTAssertEqual(loaded.root.nodeCount, 53)
    }

    func testJSONIsReadableAndStable() throws {
        let doc = Self.referenceDocument()
        let a = try MindMapCodec.encode(doc)
        let b = try MindMapCodec.encode(try MindMapCodec.decode(a))
        XCTAssertEqual(a, b, "Zweimal speichern muss dieselbe Datei ergeben")
        let text = String(decoding: a, as: UTF8.self)
        XCTAssertTrue(text.contains("\"formatVersion\" : 1"))
        XCTAssertTrue(text.contains("\"text\" : \"Referenz\""))
    }

    func testMissingOptionalFieldsGetDefaults() throws {
        let json = """
        {"root": {"id": "7E0B8C7C-1C0C-4E8E-9F0B-2B7E7C1D0A11", "text": "Alt"}}
        """
        let doc = try MindMapCodec.decode(Data(json.utf8))
        XCTAssertEqual(doc.root.text, "Alt")
        XCTAssertEqual(doc.root.children, [])
        XCTAssertFalse(doc.root.isCollapsed)
        XCTAssertEqual(doc.themeID, "blau")
    }

    func testNewerFormatVersionIsRejected() {
        let json = """
        {"formatVersion": 99, "root": {"text": "Zukunft"}}
        """
        XCTAssertThrowsError(try MindMapCodec.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? MindMapCodec.CodecError, .unsupportedFormatVersion(99))
        }
    }

    // MARK: - Baum-Operationen (Grundlage für M2)

    func testAddChildSiblingAndRemove() {
        var root = Node(text: "Wurzel")
        let a = Node(text: "A"), b = Node(text: "B"), c = Node(text: "C")
        XCTAssertTrue(root.addChild(a, to: root.id))
        XCTAssertTrue(root.addSibling(b, after: a.id))
        XCTAssertTrue(root.addChild(c, to: a.id))
        XCTAssertEqual(root.children.map(\.text), ["A", "B"])
        XCTAssertEqual(root.parentID(of: c.id), a.id)
        XCTAssertEqual(root.removeNode(id: a.id)?.nodeCount, 2)
        XCTAssertEqual(root.nodeCount, 2)
        XCTAssertNil(root.removeNode(id: root.id), "Der Hauptknoten darf nicht gelöscht werden")
    }

    func testSiblingOfRootBecomesChild() {
        var root = Node(text: "Wurzel")
        XCTAssertTrue(root.addSibling(Node(text: "X"), after: root.id))
        XCTAssertEqual(root.children.map(\.text), ["X"])
    }

    func testMoveNodePreventsCycles() {
        var doc = Self.referenceDocument()
        let ast1 = doc.root.children[0]
        let tiefer = ast1.children[0].children[0]
        XCTAssertFalse(doc.root.moveNode(id: ast1.id, toParent: tiefer.id), "Kein Umhängen in den eigenen Teilbaum")
        let ast2 = doc.root.children[1]
        XCTAssertTrue(doc.root.moveNode(id: ast1.children[0].id, toParent: ast2.id, at: 0))
        XCTAssertEqual(doc.root.node(withID: ast2.id)?.children.count, 4)
        XCTAssertEqual(doc.root.nodeCount, 53, "Beim Umhängen geht nichts verloren")
    }

    func testVisibleRowsSkipCollapsedBranches() {
        var doc = Self.referenceDocument()
        XCTAssertEqual(doc.root.visibleRows().count, 53)
        doc.root.updateNode(id: doc.root.children[0].id) { $0.isCollapsed = true }
        XCTAssertEqual(doc.root.visibleRows().count, 53 - 12)
        XCTAssertEqual(doc.root.visibleRows()[1].depth, 1)
    }

    // MARK: - Themes

    func testBundledThemesLoadAndAreComplete() throws {
        let catalog = try ThemeCatalog.decode(try Self.themesJSON())
        XCTAssertEqual(catalog.themes.count, 8)
        XCTAssertEqual(Set(catalog.themes.map(\.id)).count, 8, "IDs müssen eindeutig sein")
        XCTAssertEqual(catalog.themes.first?.id, "blau")
        for theme in catalog.themes {
            for palette in [theme.light, theme.dark] {
                XCTAssertEqual(palette.branches.count, 6, theme.id)
                for hex in [palette.canvas, palette.rootFill, palette.rootText, palette.nodeFill, palette.nodeText] + palette.branches {
                    XCTAssertNotNil(RGBAColor(hex: hex), "\(theme.id): \(hex)")
                }
            }
        }
        XCTAssertEqual(catalog.theme(withID: "gibt-es-nicht").id, "blau")
    }

    func testHexParsing() {
        XCTAssertEqual(RGBAColor(hex: "#0866E3"), RGBAColor(red: 8 / 255, green: 102 / 255, blue: 227 / 255))
        XCTAssertEqual(RGBAColor(hex: "FFFFFF80")?.alpha ?? 0, 128 / 255, accuracy: 0.0001)
        XCTAssertNil(RGBAColor(hex: "#12345"))
        XCTAssertNil(RGBAColor(hex: "#GGGGGG"))
    }

    // MARK: - Layout (Grundlage für M2)

    func testLayoutHasNoOverlapsAndBalancesSides() {
        let doc = Self.referenceDocument()
        let layout = TreeLayout.layout(root: doc.root) { node, depth in
            CGSize(width: CGFloat(20 + node.text.count * 7), height: depth == 0 ? 40 : 24)
        }
        XCTAssertEqual(layout.nodes.count, 53)
        XCTAssertEqual(layout.order.first, doc.root.id)
        let frames = Array(layout.nodes.values.map(\.frame))
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "Knoten überlappen: \(frames[i]) / \(frames[j])")
            }
        }
        let sides = doc.root.children.map { layout.nodes[$0.id]!.side }
        XCTAssertEqual(sides, [.right, .right, .left, .left])
        XCTAssertEqual(layout.nodes[doc.root.children[2].children[1].id]?.branchIndex, 2)
    }

    func testCollapsedChildrenAreNotLaidOut() {
        var doc = Self.referenceDocument()
        doc.root.updateNode(id: doc.root.children[3].id) { $0.isCollapsed = true }
        let layout = TreeLayout.layout(root: doc.root) { _, _ in CGSize(width: 80, height: 24) }
        XCTAssertEqual(layout.nodes.count, 53 - 12)
    }

    // MARK: - Themes.json finden (Xcode-Bundle oder Quellordner)

    static func themesJSON() throws -> Data {
        #if !canImport(MindMapsCore)
        if let url = Bundle.main.url(forResource: "Themes", withExtension: "json") {
            return try Data(contentsOf: url)
        }
        #endif
        let here = URL(fileURLWithPath: #filePath)
        let url = here.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MindMaps/Resources/Themes.json")
        return try Data(contentsOf: url)
    }
}
