import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M7: Querverbindungen, Fokus, Präsentation, Links, Bilder, Formeln.
final class M7Tests: XCTestCase {

    // MARK: - Hilfen

    /// Referat mit zwei Hauptästen à zwei Unterknoten (einer davon mit Enkel).
    private func referat() -> MindMapDocumentData {
        var root = Node(text: "Referat")
        var a = Node(text: "Einleitung")
        a.children = [Node(text: "Einstieg"), Node(text: "Ziel", children: [Node(text: "Detail")])]
        var b = Node(text: "Hauptteil")
        b.children = [Node(text: "These"), Node(text: "Beispiel")]
        root.children = [a, b, Node(text: "Schluss")]
        return MindMapDocumentData(root: root)
    }

    private func pngData(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    // MARK: - Datenmodell

    func testNewFieldsAndConnectionsAreSaved() throws {
        var doc = referat()
        let a = doc.root.children[0].id, b = doc.root.children[1].id
        doc.root.updateNode(id: a) {
            $0.link = "https://www.ph-freiburg.de"
            $0.formula = "E = mc^2"
            $0.image = NodeImage(asset: "bild.jpg", width: 200, height: 120)
        }
        doc.connections = [Connection(from: a, to: b, label: "führt zu", bendX: 10, bendY: -20)]
        XCTAssertEqual(try MindMapCodec.decode(try MindMapCodec.encode(doc)), doc)

        let plain = String(decoding: try MindMapCodec.encode(referat()), as: UTF8.self)
        for key in ["\"connections\"", "\"link\"", "\"image\"", "\"formula\""] {
            XCTAssertFalse(plain.contains(key), "Ohne Inhalt nicht gespeichert: \(key)")
        }
    }

    // MARK: - Querverbindungen

    func testConnectionSurvivesMovingAndDisappearsWithItsNode() {
        let document = MindMapFile(data: referat())
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)
        func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }
        var root: Node { document.data.root }
        let einstieg = root.children[0].children[0].id
        let these = root.children[1].children[0].id

        var connection: UUID?
        step { connection = actions.connect(einstieg, to: these) }
        XCTAssertNotNil(connection)
        XCTAssertNil(actions.connect(einstieg, to: these), "Keine doppelte Verbindung")
        XCTAssertNil(actions.connect(einstieg, to: einstieg), "Keine Verbindung zu sich selbst")

        // M7-Abnahme: Umhängen eines Knotens – die Verbindung bleibt korrekt.
        step { actions.move(einstieg, to: root.children[2].id) }
        XCTAssertEqual(document.data.connections.count, 1)
        XCTAssertEqual(document.data.connections[0].from, einstieg)
        XCTAssertEqual(document.data.root.parentID(of: einstieg), root.children[2].id)

        step { actions.setConnectionLabel("  Beispiel für  ", of: connection!) }
        XCTAssertEqual(document.data.connections[0].label, "Beispiel für")

        // Löschen des Zielzweigs entfernt die Verbindung mit.
        step { _ = actions.delete(root.children[1].id) }
        XCTAssertTrue(document.data.connections.isEmpty)
        undo.undo()
        XCTAssertEqual(document.data.connections.count, 1, "Rückgängig bringt Knoten und Verbindung zurück")
    }

    func testConnectionGeometryFollowsTheNodes() throws {
        var doc = referat()
        let from = doc.root.children[0].children[1].id, to = doc.root.children[1].children[1].id
        doc.connections = [Connection(from: from, to: to)]
        let scene = MapExportScene(data: doc)
        let renderer = scene.renderer
        let geometry = try XCTUnwrap(renderer.geometry(for: doc.connections[0]))
        let a = try XCTUnwrap(scene.layout.nodes[from]).frame, b = try XCTUnwrap(scene.layout.nodes[to]).frame
        XCTAssertFalse(a.insetBy(dx: 2, dy: 2).contains(geometry.start), "Beginnt am Rand, nicht in der Mitte")
        XCTAssertLessThan(hypot(geometry.start.x - a.midX, geometry.start.y - a.midY), max(a.width, a.height))
        XCTAssertLessThan(hypot(geometry.end.x - b.midX, geometry.end.y - b.midY), max(b.width, b.height))
        XCTAssertEqual(renderer.connection(at: geometry.handle), doc.connections[0].id, "Griff ist anklickbar")

        // Gebogen: Griff verschiebt sich um genau den gespeicherten Versatz.
        let bent = try XCTUnwrap(renderer.geometry(for: doc.connections[0], override: CGSize(width: 0, height: 80)))
        XCTAssertEqual(bent.handle.y, (a.midY + b.midY) / 2 + 80, accuracy: 0.01)
    }

    // MARK: - Fokus und Präsentation

    func testFocusDimsEverythingOutsideTheBranch() {
        let root = referat().root
        let ziel = root.children[0].children[1]
        let dimmed = root.idsOutsideFocus(of: ziel.id)
        XCTAssertFalse(dimmed.contains(root.id))
        XCTAssertFalse(dimmed.contains(root.children[0].id), "Weg zum Knoten bleibt sichtbar")
        XCTAssertFalse(dimmed.contains(ziel.children[0].id), "Unterknoten bleiben sichtbar")
        XCTAssertTrue(dimmed.contains(root.children[0].children[0].id), "Geschwister werden blass")
        XCTAssertTrue(dimmed.contains(root.children[1].id))
    }

    /// M7-Abnahme: Ein Referat lässt sich Zweig für Zweig vorführen.
    func testPresentationGoesBranchByBranch() {
        let root = referat().root
        let plan = PresentationPlan(root: root)
        let focusTexts = plan.steps.map { root.node(withID: $0.focus)?.text ?? "?" }
        XCTAssertEqual(focusTexts, ["Referat", "Einleitung", "Einstieg", "Ziel", "Hauptteil", "These", "Beispiel",
                                    "Schluss", "Referat"])
        XCTAssertTrue(plan.steps.last!.isOverview)
        XCTAssertEqual(plan.steps.first!.revealed, [root.id])
        for (previous, next) in zip(plan.steps, plan.steps.dropFirst()) {
            XCTAssertTrue(previous.revealed.isSubset(of: next.revealed), "Es kommt nur etwas dazu")
        }
        let ziel = root.children[0].children[1]
        XCTAssertTrue(plan.steps[3].revealed.contains(ziel.children[0].id), "Tiefere Knoten kommen mit ihrem Unterpunkt")
        XCTAssertFalse(plan.steps[3].revealed.contains(root.children[1].id), "Der nächste Ast ist noch verborgen")
        XCTAssertFalse(plan.steps[4].camera.contains(root.children[0].id), "Kamera zeigt nur den aktuellen Ast")
    }

    // MARK: - Links

    func testDocumentLinksPointToFileAndNode() throws {
        let file = URL(fileURLWithPath: "/Users/test/Documents/MindMaps/Studium/Jura – BGB AT.mindmaps")
        let node = UUID()
        let link = DocumentLink.make(file: file, node: node)
        XCTAssertTrue(link.hasPrefix("mindmaps://open?"))
        let parsed = try XCTUnwrap(DocumentLink.parse(link))
        XCTAssertEqual(parsed.file.path, file.path)
        XCTAssertEqual(parsed.node, node)
        XCTAssertNil(DocumentLink.parse("https://www.ph-freiburg.de"))
        XCTAssertEqual(DocumentLink.normalized("www.ph-freiburg.de"), "https://www.ph-freiburg.de")
        XCTAssertEqual(DocumentLink.normalized(link), link)
    }

    // MARK: - Formeln

    /// M7-Abnahme: F = G \frac{m_1 m_2}{r^2} wird korrekt gesetzt.
    func testGravitationFormulaIsTypesetCorrectly() throws {
        let atom = MathParser.parse(#"F = G \frac{m_1 m_2}{r^2}"#)
        guard case .row(let items) = atom else { return XCTFail("Zeile erwartet") }
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0], .symbol("F", .variable))
        XCTAssertEqual(items[1], .symbol("=", .relation))
        guard case .fraction(let numerator, let denominator) = items[3] else { return XCTFail("Bruch erwartet") }
        XCTAssertEqual(numerator, .row([.scripts(base: .symbol("m", .variable), sup: nil, sub: .symbol("1", .ordinary)),
                                        .scripts(base: .symbol("m", .variable), sup: nil, sub: .symbol("2", .ordinary))]))
        XCTAssertEqual(denominator, .scripts(base: .symbol("r", .variable), sup: .symbol("2", .ordinary), sub: nil))

        let box = MathTypesetter.layout(#"F = G \frac{m_1 m_2}{r^2}"#)
        XCTAssertGreaterThan(box.width, 50)
        XCTAssertGreaterThan(box.ascent, MathTypesetter.baseSize * 0.9, "Zähler steht über der Zeile")
        XCTAssertGreaterThan(box.descent, MathTypesetter.baseSize * 0.4, "Nenner steht unter der Zeile")
        let rules = box.items.compactMap { item -> CGRect? in if case .rule(let r) = item { return r } else { return nil } }
        XCTAssertEqual(rules.count, 1, "Ein Bruchstrich")
        let glyphs = box.items.compactMap { item -> (String, CGFloat)? in
            if case .glyphs(let text, _, _, _, let y) = item { return (text, y) } else { return nil }
        }
        let numeratorY = try XCTUnwrap(glyphs.first { $0.0 == "m" }).1
        let denominatorY = try XCTUnwrap(glyphs.first { $0.0 == "r" }).1
        XCTAssertLessThan(numeratorY, rules[0].minY, "m über dem Strich")
        XCTAssertGreaterThan(denominatorY, rules[0].maxY, "r unter dem Strich")
    }

    func testManyFormulasTypesetWithoutProblems() {
        let formulas = [
            #"a^2 + b^2 = c^2"#, #"\sqrt{x^2 + y^2}"#, #"\sqrt[3]{8} = 2"#, #"\sum_{i=1}^{n} i = \frac{n(n+1)}{2}"#,
            #"\int_0^1 x\,dx"#, #"\lim_{x \to 0} \frac{\sin x}{x} = 1"#, #"\alpha + \beta \geq \gamma"#,
            #"\vec{F} = m \cdot \vec{a}"#, #"\text{Dichte} = \frac{m}{V}"#, #"-x"#, #"x_{i,j}^{2}"#,
            #"\unbekannt{x}"#, #"}{"#, "", #"\frac{1}"#, #"\left( \frac{a}{b} \right)"#,
        ]
        for formula in formulas {
            let box = MathTypesetter.layout(formula)
            XCTAssertTrue(box.width.isFinite && box.ascent.isFinite && box.descent.isFinite, formula)
            if !formula.isEmpty && formula != "}{" { XCTAssertGreaterThan(box.width, 0, formula) }
        }
        let minus = MathParser.parse("-x")
        XCTAssertEqual(minus, .row([.symbol("−", .binary), .symbol("x", .variable)]))
    }

    // MARK: - Bilder

    func testLargeImagesAreScaledDown() throws {
        let prepared = try XCTUnwrap(ImageImport.prepare(pngData(width: 3000, height: 2000)))
        XCTAssertEqual(prepared.fileExtension, "jpg", "Ohne Transparenz als JPEG")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1600)
        XCTAssertEqual(Double((properties[kCGImagePropertyPixelHeight] as? Int) ?? 0), 1066.7, accuracy: 1)
        XCTAssertEqual(prepared.size.width, ImageImport.defaultWidth)
        XCTAssertEqual(prepared.size.height, (ImageImport.defaultWidth * 2 / 3).rounded(), accuracy: 1)
        XCTAssertNil(ImageImport.prepare(Data("kein Bild".utf8)))

        let image = NodeImage(asset: "a.jpg", width: 200, height: 100)
        XCTAssertEqual(image.resized(toWidth: 400), NodeImage(asset: "a.jpg", width: 400, height: 200))
        XCTAssertEqual(image.resized(toWidth: 5).width, NodeImage.minWidth)
    }

    func testPackageKeepsOnlyUsedImages() throws {
        var doc = referat()
        let id = doc.root.children[0].id
        let document = MindMapFile(data: doc)
        let actions = DocumentActions(document: document, undoManager: nil)
        XCTAssertTrue(actions.insertImage(pngData(width: 40, height: 20), into: id))
        let used = try XCTUnwrap(document.data.root.node(withID: id)?.image?.asset)
        document.addAsset(Data([1, 2, 3]), fileExtension: "jpg")   // nicht verwendet

        let wrapper = try MindMapFile.makePackage(document.data, assets: document.assets, preview: nil)
        let written = wrapper.fileWrappers?["assets"]?.fileWrappers?.keys.map { $0 } ?? []
        XCTAssertEqual(Set(written), [used])
        let reread = try MindMapFile.readPackage(wrapper)
        XCTAssertEqual(reread.data.root.node(withID: id)?.image?.asset, used)
        XCTAssertEqual(reread.assets[used], document.assets[used])

        doc = document.data
        XCTAssertEqual(doc.root.referencedAssets, [used])
    }

    // MARK: - Darstellung und Export

    @MainActor
    func testNodeMakesRoomForImageFormulaAndLink() throws {
        let metrics = NodeMetrics(theme: ThemeStore.theme(withID: "blau"))
        let plain = Node(text: "Gravitation")
        let rich = Node(text: "Gravitation", link: "https://example.org",
                        image: NodeImage(asset: "x.jpg", width: 180, height: 90),
                        formula: #"F = G \frac{m_1 m_2}{r^2}"#)
        XCTAssertGreaterThan(metrics.size(of: rich, depth: 1).height, metrics.size(of: plain, depth: 1).height + 90)
        let size = metrics.size(of: rich, depth: 1)
        let frame = CGRect(origin: .zero, size: size)
        let layout = metrics.contentLayout(of: rich, depth: 1, frame: frame)
        let image = try XCTUnwrap(layout.imageRect), formula = try XCTUnwrap(layout.formulaRect)
        let link = try XCTUnwrap(layout.linkRect)
        for rect in [image, formula, link, layout.textRect] {
            XCTAssertTrue(frame.insetBy(dx: -0.5, dy: -0.5).contains(rect), "\(rect) im Knoten")
        }
        XCTAssertLessThanOrEqual(image.maxY, layout.textRect.minY, "Bild über dem Text")
        XCTAssertGreaterThanOrEqual(formula.minY, layout.textRect.maxY, "Formel unter dem Text")

        // Nur Bild, kein Text: kein Platzhalter „…“.
        let onlyImage = Node(text: "", image: NodeImage(asset: "x.jpg", width: 100, height: 100))
        XCTAssertFalse(NodeDecor(onlyImage).showsText)
    }

    @MainActor
    func testSVGContainsFormulaImageAndConnection() throws {
        var doc = referat()
        let a = doc.root.children[0].id, b = doc.root.children[1].id
        let asset = "bild.png"
        doc.root.updateNode(id: a) {
            $0.formula = #"F = G \frac{m_1 m_2}{r^2}"#
            $0.image = NodeImage(asset: asset, width: 60, height: 30)
        }
        doc.connections = [Connection(from: a, to: b, label: "führt zu")]
        let svg = SVGExporter.svg(for: doc, assets: [asset: pngData(width: 60, height: 30)])
        XCTAssertNoThrow(try XMLDocument(xmlString: svg))
        XCTAssertTrue(svg.contains("data:image/png;base64,"), "Bild eingebettet")
        XCTAssertTrue(svg.contains("font-style=\"italic\""), "Variablen kursiv")
        XCTAssertTrue(svg.contains(">m</text>") && svg.contains(">r</text>"))
        XCTAssertTrue(svg.contains("stroke-dasharray=\"6 4\""), "Verbindung gestrichelt")
        XCTAssertTrue(svg.contains("führt zu"))

        let pdf = try MapImageExporter.pdf(doc, assets: [asset: pngData(width: 60, height: 30)],
                                           paging: .singlePage, transparent: false, title: "Test")
        XCTAssertEqual(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)?.numberOfPages, 1)
    }

    // MARK: - Lernbeispiele

    func testLearningSamplesShowTheNewFeatures() throws {
        let package = try LearningSamples.load(language: "de")
        for entry in package.documents {
            XCTAssertEqual(entry.document.connections.count, 1, "\(entry.name): eine Querverbindung als Beispiel")
            var copy = entry.document
            copy.pruneConnections()
            XCTAssertEqual(copy.connections, entry.document.connections, "Verbindung zeigt auf vorhandene Knoten")
        }
        let tutorial = try XCTUnwrap(package.documents.first { $0.name.hasPrefix("Anleitung") })
        let texts = LibraryDocument.texts(of: tutorial.document.root).joined(separator: "\n")
        XCTAssertTrue(texts.contains("Präsentation"))
        XCTAssertTrue(tutorial.document.root.ids { !$0.formula.isEmpty }.count >= 1)
        XCTAssertTrue(tutorial.document.root.ids { !$0.link.isEmpty }.count >= 1)
    }
}
