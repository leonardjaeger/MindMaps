import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M8: Layouts, Formen, Zweige, Knotenstil, eigene Themen, Export und Druck.
final class M8Tests: XCTestCase {

    // MARK: - Hilfen

    /// Einfache Größe nach Textlänge (für reine Layout-Tests ohne Schriften).
    private static func measure(_ node: Node, _ depth: Int) -> CGSize {
        let chars = CGFloat(max(node.text.count, 1))
        let width = min(chars * 7.5, 220)
        let lines = ceil(chars * 7.5 / 220)
        let shape = node.style?.shape ?? .rounded
        let padding = depth == 0 ? CGSize(width: 18, height: 10) : CGSize(width: 10, height: 5)
        return ShapeGeometry.frameSize(shape, content: CGSize(width: ceil(width), height: 17 * lines), padding: padding)
    }

    private static func layout(_ root: Node, _ style: MapStyle) -> MindMapLayout {
        MapLayoutEngine.layout(root: root, style: style, measure: measure)
    }

    /// Alle Layouts mit allen erlaubten Ausrichtungen.
    private static var allStyles: [MapStyle] {
        MapStyle.Layout.allCases.flatMap { layout in
            (layout.hasSides ? MapStyle.Sides.allCases : [.both]).map { MapStyle(layout: layout, sides: $0) }
        }
    }

    private static func center(_ node: LayoutNode) -> CGPoint {
        CGPoint(x: node.frame.midX, y: node.frame.midY)
    }

    // MARK: - Layouts

    func testReferenceDocumentHasNoOverlapsInAllFourLayouts() {
        let root = CoreTests.referenceDocument().root
        for style in Self.allStyles {
            let layout = Self.layout(root, style)
            XCTAssertEqual(layout.nodes.count, 53, "\(style.layout)")
            XCTAssertEqual(layout.kind, style.layout)
            XCTAssertTrue(MapLayoutEngine.overlaps(in: layout).isEmpty, "Überlappung in \(style.layout)/\(style.sides)")
            XCTAssertEqual(layout.order.first, root.id, "Hauptknoten zuerst")
            // Eltern vor Kindern (Zeichenreihenfolge).
            for (index, id) in layout.order.enumerated() {
                if let parent = layout.nodes[id]?.parentID {
                    XCTAssertLessThan(layout.order.firstIndex(of: parent) ?? .max, index)
                }
            }
            // Die Map ist nicht absurd lang oder breit.
            let ratio = layout.bounds.width / layout.bounds.height
            XCTAssertTrue(ratio > 0.15 && ratio < 8, "\(style.layout): Seitenverhältnis \(ratio)")
        }
    }

    func testSidesSpacingAndCollapsedBranches() {
        var root = CoreTests.referenceDocument().root
        let rootID = root.id
        let horizontalRight = Self.layout(root, MapStyle(layout: .horizontal, sides: .primary))
        XCTAssertTrue(root.children.allSatisfy { horizontalRight.nodes[$0.id]!.frame.minX > horizontalRight.nodes[rootID]!.frame.maxX })
        let horizontalLeft = Self.layout(root, MapStyle(layout: .horizontal, sides: .secondary))
        XCTAssertTrue(root.children.allSatisfy { horizontalLeft.nodes[$0.id]!.frame.maxX < horizontalLeft.nodes[rootID]!.frame.minX })
        let down = Self.layout(root, MapStyle(layout: .vertical, sides: .primary))
        XCTAssertTrue(down.nodes.values.allSatisfy { $0.id == rootID || $0.frame.minY > down.nodes[rootID]!.frame.maxY })
        let up = Self.layout(root, MapStyle(layout: .vertical, sides: .secondary))
        XCTAssertTrue(up.nodes.values.allSatisfy { $0.id == rootID || $0.frame.maxY < up.nodes[rootID]!.frame.minY })

        // Mehr Abstand → größere Map.
        var wide = MapStyle()
        wide.levelSpacing = 2
        wide.siblingSpacing = 2
        let normal = Self.layout(root, MapStyle())
        let spacious = Self.layout(root, wide)
        XCTAssertGreaterThan(spacious.bounds.width, normal.bounds.width)
        XCTAssertGreaterThan(spacious.bounds.height, normal.bounds.height)

        // Eingeklappte Zweige werden in allen Layouts nicht angeordnet.
        root.updateNode(id: root.children[0].id) { $0.isCollapsed = true }
        for style in Self.allStyles {
            XCTAssertEqual(Self.layout(root, style).nodes.count, 53 - 12, "\(style.layout)")
        }
    }

    func testRadialLayoutPlacesLevelsOnRings() throws {
        let root = CoreTests.referenceDocument().root
        let layout = Self.layout(root, MapStyle(layout: .radial))
        let rootCenter = Self.center(try XCTUnwrap(layout.nodes[root.id]))
        XCTAssertEqual(rootCenter.x, 0, accuracy: 0.001)
        XCTAssertEqual(rootCenter.y, 0, accuracy: 0.001)
        var radii: [Int: [CGFloat]] = [:]
        for node in layout.nodes.values where node.depth > 0 {
            radii[node.depth, default: []].append(hypot(node.frame.midX, node.frame.midY))
        }
        for depth in 1...3 {
            let ring = try XCTUnwrap(radii[depth])
            XCTAssertEqual(ring.max()! - ring.min()!, 0, accuracy: 0.5, "Ebene \(depth) liegt auf einem Ring")
        }
        XCTAssertLessThan(radii[1]![0], radii[2]![0])
        XCTAssertLessThan(radii[2]![0], radii[3]![0])
        // Erster Hauptast oben rechts, dann im Uhrzeigersinn.
        let angles = root.children.map { child -> CGFloat in
            let c = Self.center(layout.nodes[child.id]!)
            var a = atan2(c.y, c.x) + .pi / 2
            if a < 0 { a += 2 * .pi }
            return a
        }
        XCTAssertEqual(angles, angles.sorted())
        XCTAssertGreaterThan(layout.nodes[root.children[0].id]!.frame.midX, 0)
        XCTAssertLessThan(layout.nodes[root.children[0].id]!.frame.midY, 0)
    }

    func testCompactLayoutIndentsListsBelowTheirParent() {
        let root = CoreTests.referenceDocument().root
        let layout = Self.layout(root, MapStyle(layout: .compact))
        let rootFrame = layout.nodes[root.id]!.frame
        for branch in root.children {
            let top = layout.nodes[branch.id]!.frame
            XCTAssertGreaterThan(top.minY, rootFrame.maxY, "Hauptäste stehen unter dem Hauptknoten")
            for (index, sub) in branch.children.enumerated() {
                let frame = layout.nodes[sub.id]!.frame
                XCTAssertEqual(frame.minX, top.minX + CompactLayout.indent, accuracy: 0.001, "eingerückt")
                XCTAssertGreaterThan(frame.minY, top.maxY)
                if index > 0 {
                    let previous = layout.nodes[branch.children[index - 1].children.last!.id]!.frame
                    XCTAssertGreaterThan(frame.minY, previous.maxY, "nach den Unterknoten des Vorgängers")
                }
            }
        }
    }

    func testManualOffsetMovesTheWholeSubtree() throws {
        var doc = CoreTests.referenceDocument()
        let branch = doc.root.children[1]
        let grandchild = branch.children[0].children[0].id
        let other = doc.root.children[2].id
        let before = Self.layout(doc.root, MapStyle())
        doc.root.updateNode(id: branch.id) { $0.offset = NodeOffset(x: 40, y: -25) }
        let after = Self.layout(doc.root, MapStyle())
        for id in [branch.id, grandchild] {
            XCTAssertEqual(after.nodes[id]!.frame.minX - before.nodes[id]!.frame.minX, 40, accuracy: 0.001)
            XCTAssertEqual(after.nodes[id]!.frame.minY - before.nodes[id]!.frame.minY, -25, accuracy: 0.001)
        }
        XCTAssertEqual(after.nodes[other]!.frame, before.nodes[other]!.frame, "andere Äste bleiben stehen")
        XCTAssertTrue(after.bounds.contains(after.nodes[branch.id]!.frame))

        // Gespeichert und wieder geladen; zurücksetzen entfernt alle Positionen.
        let reread = try MindMapCodec.decode(MindMapCodec.encode(doc))
        XCTAssertEqual(reread.root.node(withID: branch.id)?.offset, NodeOffset(x: 40, y: -25))
        XCTAssertEqual(reread.root.movedNodeCount, 1)
        doc.root.clearOffsets()
        XCTAssertEqual(doc.root.movedNodeCount, 0)
    }

    func testArrowKeysInVerticalAndCompactLayouts() {
        let root = CoreTests.referenceDocument().root
        func go(_ layout: MindMapLayout, _ id: UUID?, _ direction: MoveDirection) -> UUID? {
            MapNavigation.target(from: id, direction: direction, layout: layout, rootID: root.id)
        }
        let vertical = Self.layout(root, MapStyle(layout: .vertical, sides: .primary))
        let ast1 = root.children[0], ast2 = root.children[1]
        XCTAssertTrue(root.children.map(\.id).contains(go(vertical, root.id, .down)!), "Runter: zu einem Hauptast")
        XCTAssertEqual(go(vertical, ast1.id, .right), ast2.id, "Rechts: Geschwisterknoten")
        XCTAssertEqual(go(vertical, ast2.id, .left), ast1.id)
        XCTAssertEqual(go(vertical, ast1.id, .up), root.id, "Hoch: Elternknoten")
        XCTAssertTrue(ast1.children.map(\.id).contains(go(vertical, ast1.id, .down)!))
        let leaf = ast1.children[0].children
        XCTAssertEqual(go(vertical, leaf[0].id, .down), leaf[1].id, "Liste: nächster Eintrag")
        XCTAssertEqual(go(vertical, leaf[1].id, .left), ast1.children[0].id)

        let compact = Self.layout(root, MapStyle(layout: .compact))
        let thema = ast1.children[0]
        XCTAssertEqual(go(compact, thema.id, .right), thema.children[0].id, "Rechts: erster Unterknoten")
        XCTAssertEqual(go(compact, thema.children[0].id, .left), thema.id, "Links: Elternknoten")
        XCTAssertEqual(go(compact, thema.children[2].id, .down), ast1.children[1].id, "Runter: nächste Zeile der Spalte")
        XCTAssertEqual(go(compact, ast1.children[1].id, .up), thema.children[2].id)
    }

    // MARK: - Formen und Zweige

    func testAllTenShapesContainTheirContent() {
        XCTAssertEqual(Theme.NodeShape.allCases.count, 10)
        XCTAssertEqual(Set(Theme.NodeShape.allCases.map(\.title)).count, 10)
        for shape in Theme.NodeShape.allCases {
            for content in [CGSize(width: 30, height: 17), CGSize(width: 140, height: 17), CGSize(width: 220, height: 51)] {
                let size = ShapeGeometry.frameSize(shape, content: content, padding: CGSize(width: 10, height: 5))
                let frame = CGRect(origin: CGPoint(x: 100, y: 50), size: size)
                let outline = ShapeGeometry.outline(shape, in: frame)
                if shape == .line || shape == .embedded {
                    XCTAssertTrue(outline.isEmpty, "\(shape) hat keinen Umriss")
                    continue
                }
                XCTAssertEqual(outline.last, .close, "\(shape) ist geschlossen")
                if shape == .circle || shape == .square { XCTAssertEqual(size.width, size.height, "\(shape)") }
                let box = CGRect(x: frame.midX - content.width / 2, y: frame.midY - content.height / 2,
                                 width: content.width, height: content.height)
                for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                               CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)] {
                    XCTAssertTrue(ShapeGeometry.contains(outline, corner), "\(shape): Inhalt \(content) passt nicht")
                }
                for point in outline.flattened() {
                    XCTAssertTrue(frame.insetBy(dx: -0.5, dy: -0.5).contains(point), "\(shape) bleibt im Rahmen")
                }
            }
        }
    }

    func testTaperedBranchesGetThinnerAndDockAtRoundShapes() throws {
        let parent = LayoutNode(id: UUID(), parentID: nil, frame: CGRect(x: 0, y: 0, width: 100, height: 40),
                                depth: 0, side: .center, branchIndex: -1)
        let circle = LayoutNode(id: UUID(), parentID: parent.id, frame: CGRect(x: 200, y: 100, width: 60, height: 60),
                                depth: 1, side: .right, branchIndex: 0)
        let line = BranchGeometry.centerline(parent: parent, child: circle, kind: .horizontal, style: .curved,
                                             parentInset: 6, childShape: .circle)
        let outline = BranchGeometry.taperedOutline(line, startWidth: 7, endWidth: 2)
        let points = outline.flattened(steps: 1).dropLast()
        let half = points.count / 2
        let start = hypot(points[points.startIndex].x - points[points.endIndex - 1].x,
                          points[points.startIndex].y - points[points.endIndex - 1].y)
        let end = hypot(points[points.startIndex + half - 1].x - points[points.startIndex + half].x,
                        points[points.startIndex + half - 1].y - points[points.startIndex + half].y)
        XCTAssertEqual(start, 7, accuracy: 0.5, "Anfang 7 pt breit")
        XCTAssertEqual(end, 2, accuracy: 0.5, "Ende 2 pt breit")

        // Endpunkt liegt auf dem Kreis, nicht an der Ecke des Rahmens.
        guard case .curve(let tip, _, _)? = line.last else { return XCTFail("Kurve erwartet") }
        XCTAssertEqual(hypot(tip.x - circle.frame.midX, tip.y - circle.frame.midY), 30, accuracy: 0.8)
        // Winkelige Zweige: nur senkrechte und waagerechte Stücke.
        let angled = BranchGeometry.centerline(parent: parent, child: circle, kind: .horizontal, style: .angled)
        XCTAssertEqual(angled.count, 4)
    }

    func testBranchColorAndStyleResolveOverTheme() throws {
        var root = CoreTests.referenceDocument().root
        let branch = root.children[0], sub = branch.children[1], leaf = sub.children[2]
        root.updateNode(id: sub.id) { $0.style = NodeStyle(branchColor: "#E11D48") }
        let layout = Self.layout(root, MapStyle())
        XCTAssertNil(layout.nodes[branch.id]?.branchColor)
        XCTAssertEqual(layout.nodes[sub.id]?.branchColor, "#E11D48")
        XCTAssertEqual(layout.nodes[leaf.id]?.branchColor, "#E11D48", "Unterknoten erben die Zweigfarbe")
        let context = try XCTUnwrap(root.styleContext(of: leaf.id, palette: Theme.fallback.light))
        XCTAssertEqual(context.depth, 3)
        XCTAssertEqual(context.branchHex, "#E11D48")

        let theme = Theme.fallback, palette = theme.light
        let plain = NodeAppearance.resolve(Node(text: "x"), depth: 2, branchHex: "#0866E3", theme: theme, palette: palette)
        XCTAssertEqual(plain.shape, .rounded)
        XCTAssertEqual(plain.fill, palette.nodeFill)
        XCTAssertEqual(plain.border, "#0866E3")
        let styled = NodeAppearance.resolve(
            Node(text: "x", style: NodeStyle(shape: .cloud, fill: "#FFF3BF", borderWidth: 0, textColor: "#C2410C")),
            depth: 2, branchHex: "#0866E3", theme: theme, palette: palette)
        XCTAssertEqual(styled.shape, .cloud)
        XCTAssertEqual(styled.fill, "#FFF3BF")
        XCTAssertNil(styled.border, "Rahmenstärke 0 = kein Rahmen")
        XCTAssertEqual(styled.text, "#C2410C")
        let rootLook = NodeAppearance.resolve(Node(text: "R"), depth: 0, branchHex: "#0866E3", theme: theme, palette: palette)
        XCTAssertEqual(rootLook.fill, palette.rootFill)
        XCTAssertEqual(rootLook.text, palette.rootText)
    }

    // MARK: - Speichern

    func testStylesAreSavedAndOldFilesStillOpen() throws {
        var doc = CoreTests.referenceDocument()
        doc.root.updateNode(id: doc.root.children[0].id) {
            $0.style = NodeStyle(shape: .hexagon, fill: "#D3F9D8", fontSize: 20, bold: true, italic: true)
        }
        doc.style = MapStyle(layout: .radial)
        doc.style.branchWidth = .tapered
        doc.style.levelSpacing = 1.5
        var custom = Theme.fallback
        custom.id = "eigen-test"
        custom.name = "Test"
        custom.nodeShape = .pill
        doc.customTheme = custom
        let json = String(decoding: try MindMapCodec.encode(doc), as: UTF8.self)
        let reread = try MindMapCodec.decode(Data(json.utf8))
        XCTAssertEqual(reread, doc)
        XCTAssertEqual(ThemeStore.theme(for: reread), custom, "Eigenes Thema reist im Dokument mit")

        // Ohne Stil sieht die Datei aus wie vor M8.
        let plain = String(decoding: try MindMapCodec.encode(CoreTests.referenceDocument()), as: UTF8.self)
        XCTAssertFalse(plain.contains("\"style\""))
        XCTAssertFalse(plain.contains("customTheme"))
        XCTAssertFalse(plain.contains("offset"))

        // Unbekannte Form aus einer neueren Version: der Rest des Stils bleibt.
        let future = ##"{"formatVersion":1,"themeID":"blau","root":{"id":"6B1F5C1E-6D2A-4C47-9A0E-4D2F0C1A7E11","text":"A","style":{"shape":"stern","fill":"#FF0000"}},"style":{"layout":"spirale","levelSpacing":2}}"##
        let decoded = try MindMapCodec.decode(Data(future.utf8))
        XCTAssertNil(decoded.root.style?.shape)
        XCTAssertEqual(decoded.root.style?.fill, "#FF0000")
        XCTAssertEqual(decoded.style.layout, .horizontal)
        XCTAssertEqual(decoded.style.levelSpacing, 2)
    }

    func testOwnThemeLibraryAndThemeFiles() throws {
        let suite = "MindMapsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var edited = Theme.fallback
        edited.light.branches[0] = "#123456"
        edited.nodeShape = .octagon
        let own = ThemeLibrary.makeTheme(from: edited, name: "  Mein Thema ")
        XCTAssertTrue(own.id.hasPrefix("eigen-"))
        XCTAssertEqual(own.name, "Mein Thema")
        ThemeLibrary.add(own, defaults: defaults)
        XCTAssertEqual(ThemeLibrary.themes(defaults: defaults), [own])
        XCTAssertEqual(ThemeStore.original(withID: own.id, defaults: defaults), own)

        // Datei hin und zurück; eine Datei mit der ID eines eingebauten Themas bekommt eine neue.
        let file = try ThemeLibrary.fileData(for: own)
        XCTAssertEqual(try ThemeLibrary.theme(fromFile: file), own)
        var clash = Theme.fallback
        clash.id = ThemeStore.catalog.themes[0].id
        let imported = try ThemeLibrary.theme(fromFile: ThemeLibrary.fileData(for: clash))
        XCTAssertNotEqual(imported.id, clash.id)
        XCTAssertThrowsError(try ThemeLibrary.theme(fromFile: Data("kein Thema".utf8)))

        ThemeLibrary.remove(id: own.id, defaults: defaults)
        XCTAssertTrue(ThemeLibrary.themes(defaults: defaults).isEmpty)
    }

    #if canImport(AppKit)

    // MARK: - Mit echten Schriften, Aktionen, Export, Druck (nur auf dem Mac)

    @MainActor
    func testSamplesHaveNoOverlapsWithRealFonts() throws {
        var documents = [CoreTests.referenceDocument()]
        documents += try LearningSamples.load(language: "de").documents.map(\.document)
        for var document in documents {
            func expand(_ node: inout Node) {
                node.isCollapsed = false
                for index in node.children.indices { expand(&node.children[index]) }
            }
            expand(&document.root)
            for style in Self.allStyles {
                document.style = style
                let scene = MapExportScene(data: document)
                XCTAssertTrue(MapLayoutEngine.overlaps(in: scene.layout).isEmpty,
                              "\(document.root.text): Überlappung in \(style.layout)/\(style.sides)")
            }
        }
    }

    @MainActor
    func testStyleActionsAreUndoableAndThemeGoesToAnotherDocument() throws {
        let first = MindMapFile(data: CoreTests.referenceDocument())
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: first, undoManager: undo)
        let id = first.data.root.children[0].id
        /// Jede Aktion ein eigener Schritt, wie in der App ein Klick.
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }

        step { actions.setShape(.cloud, of: id) }
        step { actions.updateNodeStyle(id) { $0.fill = "#FFF3BF" } }
        XCTAssertEqual(first.data.root.node(withID: id)?.style, NodeStyle(shape: .cloud, fill: "#FFF3BF"))
        // Stil kopieren und auf einen anderen Knoten einsetzen.
        let target = first.data.root.children[1].id
        step { actions.setNodeStyle(first.data.root.node(withID: id)?.style, of: target) }
        XCTAssertEqual(first.data.root.node(withID: target)?.style, first.data.root.node(withID: id)?.style)
        undo.undo()
        XCTAssertNil(first.data.root.node(withID: target)?.style)
        XCTAssertNotNil(first.data.root.node(withID: id)?.style, "nur der letzte Schritt ist rückgängig")
        step { actions.setNodeStyle(nil, of: id, actionName: "Stil zurücksetzen") }
        XCTAssertNil(first.data.root.node(withID: id)?.style, "Leerer Stil wird entfernt")

        // Frei verschieben summiert sich; Layoutwechsel setzt zurück, Rückgängig holt es wieder.
        step { actions.offsetNode(id, by: CGSize(width: 10, height: 5)) }
        step { actions.offsetNode(id, by: CGSize(width: 5, height: -5)) }
        XCTAssertEqual(first.data.root.node(withID: id)?.offset, NodeOffset(x: 15, y: 0))
        step { actions.setLayout(.vertical) }
        XCTAssertEqual(first.data.style.layout, .vertical)
        XCTAssertEqual(first.data.style.sides, .primary)
        XCTAssertNil(first.data.root.node(withID: id)?.offset)
        undo.undo()
        XCTAssertEqual(first.data.style.layout, .horizontal)
        XCTAssertEqual(first.data.root.node(withID: id)?.offset, NodeOffset(x: 15, y: 0))

        // Thema anpassen, als eigenes sichern und einem zweiten Dokument zuweisen.
        step { actions.updateTheme { $0.light.branches[0] = "#E11D48"; $0.nodeShape = .hexagon } }
        XCTAssertNotNil(first.data.customTheme)
        let own = ThemeLibrary.makeTheme(from: ThemeStore.theme(for: first.data), name: "Referat")
        let second = MindMapFile()
        DocumentActions(document: second, undoManager: UndoManager()).applyTheme(own)
        let reread = try MindMapCodec.decode(MindMapCodec.encode(second.data))
        XCTAssertEqual(ThemeStore.theme(for: reread), own)
        XCTAssertEqual(ThemeStore.theme(for: reread).nodeShape, .hexagon)
        // Zurück zu einem eingebauten Thema: keine Kopie mehr im Dokument.
        DocumentActions(document: second, undoManager: UndoManager()).setTheme("blau")
        XCTAssertNil(second.data.customTheme)
    }

    @MainActor
    func testAllTenShapesAreExportedToSVGAndPDF() throws {
        var root = Node(text: "Formen")
        for shape in Theme.NodeShape.allCases {
            root.children.append(Node(text: shape.title, style: NodeStyle(shape: shape)))
        }
        let doc = MindMapDocumentData(root: root)
        let scene = MapExportScene(data: doc)
        let svg = SVGExporter.svg(for: doc)
        XCTAssertNoThrow(try XMLDocument(xmlString: svg))
        for child in root.children {
            let shape = try XCTUnwrap(child.style?.shape)
            let frame = try XCTUnwrap(scene.layout.nodes[child.id]).frame
            let outline = ShapeGeometry.outline(shape, in: frame)
            if outline.isEmpty {
                if shape == .line {
                    XCTAssertTrue(svg.contains(ShapeGeometry.underline(frame).svgPathData()), "Linie fehlt im SVG")
                }
            } else {
                XCTAssertTrue(svg.contains(outline.svgPathData()), "\(shape.title): Umriss fehlt im SVG")
            }
            XCTAssertTrue(svg.contains(">\(shape.title)</tspan>"), "\(shape.title): Text fehlt")
        }
        let pdf = try MapImageExporter.pdf(doc, paging: .singlePage, transparent: false, title: "Formen")
        XCTAssertEqual(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)?.numberOfPages, 1)
    }

    @MainActor
    func testPrintAndExportUseTheScreenLayout() throws {
        var doc = CoreTests.referenceDocument()
        doc.style = MapStyle(layout: .radial)
        doc.root.updateNode(id: doc.root.children[0].id) { $0.style = NodeStyle(shape: .circle, fontSize: 22) }
        let theme = ThemeStore.theme(for: doc)
        let metrics = NodeMetrics(theme: theme, style: doc.style)
        // So rechnet die Arbeitsfläche (MapCanvasView) …
        let screen = MapLayoutEngine.layout(root: doc.root, style: doc.style) { metrics.size(of: $0, depth: $1) }
        // … und so Export und Druck.
        XCTAssertEqual(MapExportScene(data: doc).layout, screen)
        let tiling = MapImageExporter.tiling(doc, paging: .singlePage)
        let pdf = try MapImageExporter.pdf(doc, paging: .singlePage, transparent: false, title: "Druck")
        let page = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdf as CFData)!)?.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.mediaBox).width, tiling.pageSize.width, accuracy: 0.5)
        XCTAssertEqual(page.getBoxRect(.mediaBox).height, tiling.pageSize.height, accuracy: 0.5)
        let a4 = MapImageExporter.tiling(doc, paging: .a4)
        XCTAssertGreaterThanOrEqual(a4.tiles.count, 1)
        XCTAssertEqual(max(a4.pageSize.width, a4.pageSize.height), 842, accuracy: 0.5)
    }

    #endif
}
