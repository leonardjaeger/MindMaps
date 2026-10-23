import XCTest
import AppKit
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M5: Import und Export (Markdown, OPML, Klartext, FreeMind, RTF, TextBundle, PNG, PDF, SVG).
final class M5Tests: XCTestCase {

    // MARK: - Hilfen

    /// Das Referenz-Dokument aus `Docs/` (wird nur gelesen, nie verändert).
    private func reference() throws -> MindMapDocumentData {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Docs/Referenz.mindmaps/document.json")
        return try MindMapCodec.decode(Data(contentsOf: url))
    }

    /// Struktur als Liste „Ebene|Text“ – Vergleich ohne IDs und Einklapp-Zustand.
    private func shape(_ node: Node, _ depth: Int = 0) -> [String] {
        ["\(depth)|\(node.text)"] + node.children.flatMap { shape($0, depth + 1) }
    }

    private func tree(_ texts: String...) -> Node {
        Node(text: texts[0], children: texts.dropFirst().map { Node(text: $0) })
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapsM5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // MARK: - Markdown

    func testReferenceDocumentSurvivesMarkdownRoundTrip() throws {
        let doc = try reference()
        XCTAssertGreaterThanOrEqual(doc.root.nodeCount, 50)
        let markdown = MarkdownFormat.export(doc.root)
        XCTAssertTrue(markdown.hasPrefix("# \(doc.root.text)\n"))
        let back = try MarkdownFormat.parse(markdown, fallbackTitle: "Datei")
        XCTAssertEqual(shape(back), shape(doc.root), "Referenz → Markdown → Import ergibt dieselbe Struktur")
    }

    func testMarkdownRoundTripKeepsSpecialTextAndLineBreaks() throws {
        var root = Node(text: "Übersicht: *wichtig* & <neu>")
        var branch = Node(text: "1. Kapitel")
        branch.children = [Node(text: "Zeile eins\nZeile zwei"), Node(text: "#hashtag"), Node(text: "")]
        branch.children[0].children = [Node(text: "- kein Aufzählungszeichen")]
        root.children = [branch, Node(text: "Emoji 🙂 und Umlaute äöüß")]
        let back = try MarkdownFormat.parse(MarkdownFormat.export(root), fallbackTitle: "x")
        XCTAssertEqual(shape(back), shape(root))
    }

    func testMarkdownImportOfForeignFile() throws {
        let text = """
        Titel
        =====

        Ein einleitender Satz,
        der weitergeht.

        ## Erster Teil
        - Punkt A
          - Unterpunkt A1
        * [x] Punkt B

        ## Zweiter Teil ##
        1. Eins
        2. Zwei
           mit Fortsetzung

        ---
        ```
        let code = 1
        ```
        """
        let root = try MarkdownFormat.parse(text, fallbackTitle: "Datei")
        XCTAssertEqual(shape(root), [
            "0|Titel",
            "1|Ein einleitender Satz, der weitergeht.",
            "1|Erster Teil",
            "2|Punkt A",
            "3|Unterpunkt A1",
            "2|Punkt B",
            "1|Zweiter Teil",
            "2|Eins",
            "2|Zwei\nmit Fortsetzung",
            "2|let code = 1",
        ])
    }

    func testMarkdownWithSeveralTopHeadingsUsesFileName() throws {
        let root = try MarkdownFormat.parse("# Eins\n# Zwei\n- a\n", fallbackTitle: "Notizen")
        XCTAssertEqual(shape(root), ["0|Notizen", "1|Eins", "1|Zwei", "2|a"])
        XCTAssertThrowsError(try MarkdownFormat.parse("\n  \n", fallbackTitle: "leer")) { error in
            XCTAssertEqual(error as? MindMapImporter.ImportError, .empty)
        }
    }

    // MARK: - Klartext

    func testPlainTextRoundTripAndSpaceIndentation() throws {
        let doc = try reference()
        let back = try PlainTextFormat.parse(PlainTextFormat.export(doc.root), fallbackTitle: "x")
        XCTAssertEqual(shape(back), shape(doc.root))

        let spaces = "Projekt\n  Planung\n    Termine\n  Umsetzung\n\r\n"
        XCTAssertEqual(shape(try PlainTextFormat.parse(spaces, fallbackTitle: "x")),
                       ["0|Projekt", "1|Planung", "2|Termine", "1|Umsetzung"])
    }

    // MARK: - OPML

    func testOPMLRoundTripAndEscaping() throws {
        let doc = try reference()
        let opml = OPMLFormat.export(doc.root)
        XCTAssertNotNil(try? XMLDocument(xmlString: opml), "gültiges XML")
        XCTAssertEqual(shape(try OPMLFormat.parse(Data(opml.utf8), fallbackTitle: "x")), shape(doc.root))

        let tricky = tree("A & B <C> \"D\"", "Zeile 1\nZeile 2", "Tab\tda")
        let back = try OPMLFormat.parse(Data(OPMLFormat.export(tricky).utf8), fallbackTitle: "x")
        XCTAssertEqual(shape(back), shape(tricky))
    }

    func testOPMLFromOtherProgramWithSeveralTopItems() throws {
        let opml = """
        <?xml version="1.0"?>
        <opml version="1.0"><head><title>Lernplan</title></head>
        <body><outline text="Mathe"><outline title="Brüche"/></outline><outline text="Deutsch" _note="x"/></body></opml>
        """
        let root = try OPMLFormat.parse(Data(opml.utf8), fallbackTitle: "Datei")
        XCTAssertEqual(shape(root), ["0|Lernplan", "1|Mathe", "2|Brüche", "1|Deutsch"])
        XCTAssertThrowsError(try OPMLFormat.parse(Data("<html></html>".utf8), fallbackTitle: "x"))
    }

    // MARK: - FreeMind

    func testFreeMindRoundTripKeepsFoldedBranches() throws {
        var doc = try reference()
        let folded = doc.root.children[0].id
        doc.root.updateNode(id: folded) { $0.isCollapsed = true }
        let mm = FreeMindFormat.export(doc.root)
        XCTAssertTrue(mm.contains("POSITION=\"right\"") && mm.contains("POSITION=\"left\""))
        let back = try FreeMindFormat.parse(Data(mm.utf8), fallbackTitle: "x")
        XCTAssertEqual(shape(back), shape(doc.root))
        XCTAssertTrue(back.children[0].isCollapsed)
        XCTAssertFalse(back.children[1].isCollapsed)
    }

    func testFreeMindRichContentNode() throws {
        let mm = """
        <map version="1.0.1"><node TEXT="Wurzel"><node POSITION="right">
        <richcontent TYPE="NODE"><html><body><p>Erste   Zeile</p><p>Zweite</p></body></html></richcontent>
        </node></node></map>
        """
        let root = try FreeMindFormat.parse(Data(mm.utf8), fallbackTitle: "x")
        XCTAssertEqual(shape(root), ["0|Wurzel", "1|Erste Zeile\nZweite"])
    }

    // MARK: - RTF und TextBundle

    func testRTFOpensWithAllTexts() throws {
        let root = tree("Umlaute äöü 🙂", "Klammern {und} \\Backslash", "Zweiter Ast")
        let rtf = RTFFormat.export(root)
        XCTAssertTrue(rtf.hasPrefix("{\\rtf1"))
        let text = try XCTUnwrap(NSAttributedString(rtf: Data(rtf.utf8), documentAttributes: nil)).string
        for line in shape(root) {
            XCTAssertTrue(text.contains(line.components(separatedBy: "|")[1]), line)
        }
    }

    func testTextBundleExportAndImport() throws {
        let doc = try reference()
        let folder = try temporaryFolder()
        let url = folder.appendingPathComponent("Referenz.textbundle")
        let wrapper = try XCTUnwrap(TextExporter.fileWrapper(for: doc, format: .textBundle))
        try ExportFiles.write(wrapper, to: url)
        let info = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("info.json"))) as? [String: Any]
        XCTAssertEqual(info?["type"] as? String, "net.daringfireball.markdown")
        let imported = try MindMapImporter.importFile(at: url)
        XCTAssertEqual(shape(imported.root), shape(doc.root))

        // Nochmal an dieselbe Stelle: ersetzt das Paket, statt zu scheitern.
        XCTAssertNoThrow(try ExportFiles.write(wrapper, to: url))
    }

    // MARK: - Import über die Dateiendung

    func testImporterChoosesFormatByExtension() throws {
        let folder = try temporaryFolder()
        let files: [(String, String)] = [
            ("Notiz.md", "# Thema\n- a\n"),
            ("Liste.txt", "Thema\n\ta\n"),
            ("Plan.opml", OPMLFormat.export(tree("Thema", "a"))),
            ("Karte.mm", FreeMindFormat.export(tree("Thema", "a"))),
        ]
        for (name, content) in files {
            let url = folder.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            XCTAssertTrue(MindMapImporter.canImport(url))
            let doc = try MindMapImporter.importFile(at: url)
            XCTAssertEqual(shape(doc.root), ["0|Thema", "1|a"], name)
        }
        let latin1 = folder.appendingPathComponent("Alt.txt")
        try Data("Gr\u{FC}\u{DF}e\n\tStra\u{DF}e\n".data(using: .windowsCP1252)!).write(to: latin1)
        XCTAssertEqual(shape(try MindMapImporter.importFile(at: latin1).root), ["0|Grüße", "1|Straße"])

        XCTAssertThrowsError(try MindMapImporter.importFile(at: folder.appendingPathComponent("Bild.jpg"))) { error in
            XCTAssertEqual(error as? MindMapImporter.ImportError, .unsupported("jpg"))
        }
    }

    func testImportCreatesLibraryDocument() throws {
        let folder = try temporaryFolder()
        let source = folder.appendingPathComponent("Referat: Wasser.md")
        try "# Wasser\n## Kreislauf\n- Verdunstung\n".write(to: source, atomically: true, encoding: .utf8)
        let library = folder.appendingPathComponent("Bibliothek", isDirectory: true)
        let created = try LibraryStore.createDocument(MindMapImporter.importFile(at: source),
                                                      named: ImportController.documentName(for: source), in: library)
        XCTAssertEqual(created.lastPathComponent, "Referat- Wasser.mindmaps")
        var cache: [URL: LibraryDocument] = [:]
        let docs = LibraryScanner.scan(library, cache: &cache).documents
        XCTAssertEqual(docs.first.map { shape($0.data.root) }, ["0|Wasser", "1|Kreislauf", "2|Verdunstung"])
    }

    // MARK: - Seitenaufteilung für PDF

    func testSmallMapFitsOnOneA4Page() {
        let tiling = PageTiling.a4(content: CGRect(x: -400, y: -150, width: 800, height: 300), occupied: [])
        XCTAssertEqual(tiling.tiles.count, 1)
        XCTAssertTrue(tiling.isLandscape, "breite Map → Querformat")
        XCTAssertLessThanOrEqual(tiling.scale, 1)
        XCTAssertGreaterThanOrEqual(tiling.scale, 0.6)
    }

    func testLargeMapIsSpreadOverReadablePagesWithoutEmptyOnes() {
        let content = CGRect(x: -2000, y: -1500, width: 4000, height: 3000)
        let occupied = [CGRect(x: -1990, y: -1490, width: 100, height: 30),   // oben links
                        CGRect(x: 1800, y: 1400, width: 100, height: 30),     // unten rechts
                        CGRect(x: -50, y: -15, width: 100, height: 30)]       // Mitte
        let tiling = PageTiling.a4(content: content, occupied: occupied)
        XCTAssertEqual(tiling.scale, 0.75, "Text bleibt lesbar")
        XCTAssertGreaterThan(tiling.rows * tiling.columns, tiling.tiles.count, "leere Seiten fallen weg")
        for rect in occupied {
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            for corner in corners {
                XCTAssertTrue(tiling.tiles.contains { $0.rect.contains(corner) }, "\(rect) ist auf den Seiten zu sehen")
            }
        }
        let printable = CGSize(width: tiling.pageSize.width - 2 * tiling.margin,
                               height: tiling.pageSize.height - 2 * tiling.margin)
        XCTAssertEqual(tiling.tiles[0].rect.width * tiling.scale, printable.width, accuracy: 0.01)
    }

    // MARK: - Bild-Export (SVG, PNG, PDF)

    @MainActor
    func testSVGIsValidXMLWithAllTexts() throws {
        let doc = try reference()
        let svg = SVGExporter.svg(for: doc)
        let xml = try XMLDocument(xmlString: svg)
        XCTAssertEqual(xml.rootElement()?.name, "svg")
        XCTAssertEqual(xml.rootElement()?.attribute(forName: "xmlns")?.stringValue ?? xml.rootElement()?.uri,
                       "http://www.w3.org/2000/svg")
        let spans = try xml.nodes(forXPath: "//*[local-name()='tspan']").compactMap(\.stringValue)
        let joined = spans.joined(separator: " ")
        for node in visibleTexts(doc.root) {
            for word in node.split(separator: " ") {
                XCTAssertTrue(joined.contains(word), "„\(word)“ fehlt im SVG")
            }
        }
    }

    private func visibleTexts(_ node: Node) -> [String] {
        [node.text] + (node.isCollapsed ? [] : node.children.flatMap(visibleTexts))
    }

    @MainActor
    func testPNGExportHasExpectedPixelSize() throws {
        let doc = try reference()
        let png = try MapImageExporter.png(doc, scale: 2, transparent: true)
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        let expected = MapImageExporter.pngPixelSize(doc, scale: 2)
        XCTAssertEqual(CGFloat(rep.pixelsWide), expected.width, accuracy: 1)
        XCTAssertEqual(CGFloat(rep.pixelsHigh), expected.height, accuracy: 1)
        XCTAssertTrue(rep.hasAlpha)
    }

    @MainActor
    func testPDFExportHasOnePagePerTile() throws {
        // Großes Dokument: 12 Äste × 8 × 4 Knoten.
        var root = Node(text: "Sehr große Mindmap")
        for a in 1...12 {
            var branch = Node(text: "Ast \(a) mit etwas längerem Text")
            for b in 1...8 {
                var sub = Node(text: "Thema \(a).\(b)")
                for c in 1...4 { sub.children.append(Node(text: "Punkt \(a).\(b).\(c) mit Erklärung")) }
                branch.children.append(sub)
            }
            root.children.append(branch)
        }
        let big = MindMapDocumentData(root: root)

        let tiling = MapImageExporter.tiling(big, paging: .a4)
        XCTAssertGreaterThan(tiling.tiles.count, 1)
        let pdf = try MapImageExporter.pdf(big, paging: .a4, transparent: false, title: "Groß")
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdf as CFData)!))
        XCTAssertEqual(document.numberOfPages, tiling.tiles.count)
        let box = try XCTUnwrap(document.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(Set([box.width.rounded(), box.height.rounded()]), [595, 842], "A4")

        let single = try MapImageExporter.pdf(try reference(), paging: .singlePage, transparent: true, title: "Referenz")
        XCTAssertEqual(CGPDFDocument(CGDataProvider(data: single as CFData)!)?.numberOfPages, 1)
    }
}
