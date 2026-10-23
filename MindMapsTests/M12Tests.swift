import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Tests für M12: Leistung mit 1.000 Knoten, Barrierefreiheit, Englisch.
final class M12Tests: XCTestCase {

    // MARK: - Leistung

    /// Einfache Größe nach Textlänge (für Layout-Tests ohne Schriften).
    private static func measure(_ node: Node, _ depth: Int) -> CGSize {
        let chars = CGFloat(max(node.text.count, 1))
        return CGSize(width: min(chars * 7.5, 220) + 20, height: 17 * ceil(chars * 7.5 / 220) + 10)
    }

    func testLargeSampleHasAThousandVariedNodes() {
        let data = LargeSample.document()
        XCTAssertEqual(data.root.nodeCount, 1000)
        XCTAssertEqual(LargeSample.document(), data, "immer dieselbe Map")
        XCTAssertEqual(LargeSample.document(nodeCount: 250).root.nodeCount, 250)
        XCTAssertEqual(LargeSample.document(nodeCount: 2000).root.nodeCount, 2000)
        XCTAssertEqual(data.root.children.count, 8)
        XCTAssertGreaterThan(data.root.ids { $0.task != nil }.count, 100)
        XCTAssertGreaterThan(data.root.ids { !$0.tags.isEmpty }.count, 50)
        XCTAssertGreaterThan(data.root.ids { !$0.note.isEmpty }.count, 50)
        XCTAssertGreaterThan(data.root.ids { !$0.formula.isEmpty }.count, 5)
        XCTAssertEqual(data.root.subtreeIDs.count, 1000, "IDs eindeutig")
    }

    func testThousandNodesLayOutQuicklyWithoutOverlaps() throws {
        let data = LargeSample.document()
        let json = try MindMapCodec.encode(data)
        var start = Date()
        let decoded = try MindMapCodec.decode(json)
        let decodeTime = Date().timeIntervalSince(start)
        XCTAssertEqual(decoded, data)
        XCTAssertLessThan(decodeTime, 0.5, "Datei lesen")

        for layout in MapStyle.Layout.allCases {
            start = Date()
            let result = MapLayoutEngine.layout(root: data.root, style: MapStyle(layout: layout), measure: Self.measure)
            let time = Date().timeIntervalSince(start)
            print("M12 Layout \(layout): \(Int(time * 1000)) ms")
            XCTAssertEqual(result.nodes.count, 1000)
            XCTAssertTrue(MapLayoutEngine.overlaps(in: result).isEmpty, "\(layout)")
            XCTAssertLessThan(time, 0.5, "\(layout)")
        }
        start = Date()
        XCTAssertEqual(data.root.visibleRows().count, 1000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3, "Outline")
    }

    func testVisibleRegionInMapCoordinates() {
        let viewport = Viewport(zoom: 2, offset: CGPoint(x: 100, y: -50))
        let visible = viewport.toMap(CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(visible, CGRect(x: -50, y: 25, width: 400, height: 300))
        XCTAssertEqual(viewport.toView(visible), CGRect(x: 0, y: 0, width: 800, height: 600))
    }


    // MARK: - Sprachen

    func testPlaceholdersAreFilledInEveryLanguage() {
        XCTAssertEqual(Localization.fill("„%@“: %@", ["Referat", "fehlt"]), "„Referat“: fehlt")
        XCTAssertEqual(Localization.fill("%2$@ before %1$@", ["A", "B"]), "B before A")
        XCTAssertEqual(Localization.fill("Maßstab %@ %%", ["80"]), "Maßstab 80 %")
        XCTAssertEqual(Localization.fill("%@ und %@", ["eins"]), "eins und ")
        XCTAssertEqual(Localization.fill("100 % sicher", []), "100 % sicher", "einzelnes Prozentzeichen bleibt")
        // Ohne Übersetzung bleibt der deutsche Text.
        XCTAssertEqual(L("Kein Schlüssel in der Tabelle"), "Kein Schlüssel in der Tabelle")
        XCTAssertEqual(L("Kein Schlüssel: %@ Knoten", "5"), "Kein Schlüssel: 5 Knoten")
    }

    // MARK: - Barrierefreiheit

    func testVoiceOverDescribesNodes() {
        let note = Node(text: "Quellen", note: "Bibliothek", tags: ["Wichtig", "Prüfung"], task: .open, link: "https://x.de")
        let branch = Node(text: "Gliederung", children: [note, Node(text: "A", task: .done), Node(text: "B")])
        let root = Node(text: "Referat", children: [branch])

        XCTAssertEqual(NodeSpeech.details(NodeSpeech.facts(of: root, depth: 0)),
                       "Hauptknoten, 1 Unterknoten, 1 von 2 Aufgaben erledigt")
        XCTAssertEqual(NodeSpeech.details(NodeSpeech.facts(of: branch, depth: 1)),
                       "Ebene 1, 3 Unterknoten, 1 von 2 Aufgaben erledigt")
        XCTAssertEqual(NodeSpeech.sentence(for: note, depth: 2),
                       "Quellen, Ebene 2, Aufgabe offen, mit Notiz, mit Link, Tags: Wichtig, Prüfung")
        var collapsed = branch
        collapsed.isCollapsed = true
        collapsed.task = .open
        XCTAssertEqual(NodeSpeech.details(NodeSpeech.facts(of: collapsed, depth: 1)),
                       "Ebene 1, eingeklappt, Aufgabe teilweise erledigt")
        XCTAssertEqual(NodeSpeech.label("   "), "Ohne Text")

        // Die Gliederung sagt dasselbe (ohne Zahl der Unterknoten).
        let rows = root.visibleRows()
        XCTAssertEqual(NodeSpeech.details(NodeSpeech.facts(of: rows[1])),
                       "Ebene 1, hat Unterknoten, 1 von 2 Aufgaben erledigt")
        XCTAssertEqual(NodeSpeech.details(NodeSpeech.facts(of: rows[2])),
                       "Ebene 2, Aufgabe offen, mit Notiz, mit Link, Tags: Wichtig, Prüfung")
    }

    func testBuiltInThemesHaveEnoughContrast() throws {
        XCTAssertEqual(ColorContrast.ratio("#000000", "#FFFFFF") ?? 0, 21, accuracy: 0.01)
        XCTAssertEqual(ColorContrast.ratio("#777777", "#777777") ?? 0, 1, accuracy: 0.01)
        XCTAssertNil(ColorContrast.ratio("kein", "#FFFFFF"))

        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MindMaps/Resources/Themes.json")
        let catalog = try ThemeCatalog.decode(Data(contentsOf: url))
        XCTAssertEqual(catalog.themes.count, 8)
        for theme in catalog.themes {
            XCTAssertEqual(ColorContrast.issues(in: theme), [], theme.id)
        }

        // Eigene Farben mit zu wenig Kontrast werden erkannt.
        var weak = catalog.themes[0]
        weak.light.nodeText = "#BBBBBB"
        weak.dark.branches[0] = weak.dark.canvas
        let issues = ColorContrast.issues(in: weak)
        XCTAssertTrue(issues.contains { $0.what == "Text auf Knoten" && !$0.dark })
        XCTAssertTrue(issues.contains { $0.what == "Zweigfarbe 1" && $0.dark && $0.minimum == 3 })
        XCTAssertTrue(issues.allSatisfy { $0.ratio < $0.minimum })
        XCTAssertTrue(issues[0].description.contains(": 1 – nötig sind 4"))

        let look = NodeAppearance(shape: .rounded, fill: "#FFF3BF", border: nil, borderWidth: 0,
                                  text: "#F5D76E", accent: "#000000", branch: "#000000")
        XCTAssertNotNil(ColorContrast.textIssue(look, canvas: "#FFFFFF"))
        var readable = look
        readable.text = "#1B2330"
        XCTAssertNil(ColorContrast.textIssue(readable, canvas: "#FFFFFF"))
    }

    #if canImport(AppKit)

    // MARK: - Nur auf dem Mac: echte Schriften und Zeichnen

    /// Zeichnet ein Bild der Arbeitsfläche (1200 × 800) – wie ein Bild beim Verschieben.
    @MainActor
    private static func frame(_ renderer: MapRenderer, _ viewport: Viewport, culling: Bool = true) -> CGImage? {
        let size = CGSize(width: 1200, height: 800)
        let view = Canvas { context, size in
            context.translateBy(x: viewport.offset.x, y: viewport.offset.y)
            context.scaleBy(x: viewport.zoom, y: viewport.zoom)
            var state = MapRenderer.State()
            state.visibleRect = culling ? viewport.toMap(CGRect(origin: .zero, size: size)) : nil
            state.zoom = viewport.zoom
            renderer.draw(in: &context, state: state)
        }
        .frame(width: size.width, height: size.height)
        let image = ImageRenderer(content: view)
        image.scale = 1
        return image.cgImage
    }

    @MainActor
    private static func prepare(_ data: MindMapDocumentData) -> (MapRenderer, MindMapLayout) {
        let theme = ThemeStore.theme(for: data)
        let metrics = NodeMetrics(theme: theme, style: data.style)
        let layout = MapLayoutEngine.layout(root: data.root, style: data.style) { metrics.size(of: $0, depth: $1) }
        let renderer = MapRenderer(root: data.root, layout: layout, theme: theme,
                                   palette: theme.palette(dark: false), metrics: metrics)
        return (renderer, layout)
    }

    @MainActor
    func testThousandNodeDocumentOpensInUnderTwoSeconds() throws {
        let json = try MindMapCodec.encode(LargeSample.document())
        TextSizeCache.shared.removeAll()
        let start = Date()
        let data = try MindMapCodec.decode(json)
        let (renderer, layout) = Self.prepare(data)
        let window = CGSize(width: 1200, height: 800)
        XCTAssertNotNil(Self.frame(renderer, .fitting(layout.bounds, in: window, maxFitZoom: 1)))
        _ = data.root.visibleRows()
        let elapsed = Date().timeIntervalSince(start)
        print("M12 Öffnen mit 1.000 Knoten: \(Int(elapsed * 1000)) ms")
        XCTAssertLessThan(elapsed, 2)
        XCTAssertGreaterThan(TextSizeCache.shared.count, 500, "Textgrößen gemerkt")

        // Zweites Layout (z. B. nach einer Änderung) braucht die Texte nicht neu zu vermessen.
        let again = Date()
        _ = Self.prepare(data)
        let relayout = Date().timeIntervalSince(again)
        print("M12 Layout nach Änderung: \(Int(relayout * 1000)) ms")
        XCTAssertLessThan(relayout, 0.5)
    }

    @MainActor
    func testScrollingThroughAThousandNodesStaysSmooth() {
        let (renderer, layout) = Self.prepare(LargeSample.document())
        let top = layout.bounds.minY
        var total: TimeInterval = 0
        let frames = 30
        for step in 0..<frames {
            let viewport = Viewport(zoom: 1, offset: CGPoint(x: 600 - layout.bounds.midX,
                                                             y: -top - CGFloat(step) * 120))
            let start = Date()
            XCTAssertNotNil(Self.frame(renderer, viewport))
            total += Date().timeIntervalSince(start)
        }
        let average = total / Double(frames)
        print("M12 Bild beim Scrollen (Zoom 100 %): \(Int(average * 1000)) ms")
        XCTAssertLessThan(average, 1.0 / 20, "flüssig: mindestens 20 Bilder pro Sekunde, auch im Debug-Build")

        // Ganz herausgezoomt: Balken statt Text.
        let overview = Viewport.fitting(layout.bounds, in: CGSize(width: 1200, height: 800), maxFitZoom: 1)
        XCTAssertLessThan(overview.zoom, MapRenderer.greekingZoom)
        let start = Date()
        XCTAssertNotNil(Self.frame(renderer, overview))
        let overviewTime = Date().timeIntervalSince(start)
        print("M12 Bild der Übersicht (Zoom \(Int(overview.zoom * 100)) %): \(Int(overviewTime * 1000)) ms")
        XCTAssertLessThan(overviewTime, 0.25)
    }

    @MainActor
    func testTextSizesAreMeasuredOnce() {
        let theme = ThemeStore.theme(for: MindMapDocumentData.newDocument())
        let metrics = NodeMetrics(theme: theme, style: MapStyle())
        let node = Node(text: "Ein Knoten mit einem Text, der umbricht, weil er länger ist als erlaubt")
        TextSizeCache.shared.removeAll()
        let first = metrics.textSize(of: node, depth: 2)
        XCTAssertEqual(TextSizeCache.shared.count, 1)
        XCTAssertEqual(metrics.textSize(of: node, depth: 2), first)
        XCTAssertEqual(TextSizeCache.shared.count, 1)
        XCTAssertGreaterThan(first.height, 20, "mehrzeilig")
        XCTAssertLessThanOrEqual(first.width, NodeMetrics.maxTextWidth)
        // Andere Ebene = andere Schrift = eigene Messung.
        _ = metrics.textSize(of: node, depth: 0)
        XCTAssertEqual(TextSizeCache.shared.count, 2)
    }


    // MARK: - Nur auf dem Mac: Englisch

    /// Alle Texte, die im Code mit `L("…")` übersetzt werden, samt Platzhaltern.
    private static func codeKeys() throws -> Set<String> {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MindMaps")
        let pattern = try NSRegularExpression(pattern: #"\bL\(\s*"((?:[^"\\\n]|\\.)*)""#)
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 50)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                keys.insert(text[range].replacingOccurrences(of: "\\\\", with: "\\")
                                .replacingOccurrences(of: "\\\"", with: "\""))
            }
        }
        return keys
    }

    private static func englishTable(_ name: String) throws -> [String: String] {
        let path = try XCTUnwrap(Bundle.main.path(forResource: name, ofType: "strings", inDirectory: nil,
                                                  forLocalization: "en"), "\(name).strings (en) fehlt")
        return try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
    }

    private static func placeholders(_ text: String) -> Int {
        text.components(separatedBy: "%@").count - 1
            + (try! NSRegularExpression(pattern: #"%\d\$@"#)).numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    func testEnglishTranslationsCoverAllTexts() throws {
        let english = try Self.englishTable("Localizable")
        XCTAssertGreaterThan(english.count, 500)
        let keys = try Self.codeKeys()
        XCTAssertGreaterThan(keys.count, 300, "Schlüssel im Code gefunden")
        let missing = keys.filter { english[$0] == nil }.sorted()
        XCTAssertEqual(missing, [], "ohne englische Übersetzung")
        for (key, value) in english {
            XCTAssertEqual(Self.placeholders(key), Self.placeholders(value), "Platzhalter: \(key)")
            XCTAssertEqual(key.contains("%%"), value.contains("%%"), "Prozent: \(key)")
            XCTAssertFalse(value.isEmpty, key)
        }
        for (key, value) in try Self.englishTable("AppShortcuts") {
            XCTAssertTrue(value.contains("${applicationName}"), key)
        }
        let info = try Self.englishTable("InfoPlist")
        XCTAssertEqual(info["MindMaps-Dokument"], "MindMaps Document")
        XCTAssertNotNil(info["NSRemindersFullAccessUsageDescription"])
    }

    func testGermanAndEnglishTexts() throws {
        // Die Tests laufen auf Deutsch (Schema: -AppleLanguages (de)).
        XCTAssertEqual(L("Knoten hinzufügen"), "Knoten hinzufügen")
        XCTAssertEqual(L("„%@“ gibt es an diesem Ort schon.", "Biologie"), "„Biologie“ gibt es an diesem Ort schon.")
        XCTAssertEqual(MapStyle.Layout.radial.title, "Radial")

        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try XCTUnwrap(Bundle(path: path))
        func en(_ key: String) -> String { english.localizedString(forKey: key, value: nil, table: nil) }
        XCTAssertEqual(en("Knoten hinzufügen"), "Add Node")
        XCTAssertEqual(en("Zentrales Thema"), "Central Topic")
        XCTAssertEqual(Localization.fill(en("„%@“ gibt es an diesem Ort schon."), ["Biology"]),
                       "“Biology” already exists at this location.")
        XCTAssertEqual(en("Schwarzwald"), "Black Forest")
        XCTAssertEqual(Bundle.main.localizations.contains("de") && Bundle.main.localizations.contains("en"), true)
    }

    func testEnglishGuide() throws {
        let package = try LearningSamples.load(language: "en")
        XCTAssertEqual(package.folder, "Guide")
        XCTAssertEqual(package.documents.count, 1)
        let guide = package.documents[0]
        XCTAssertTrue(guide.name.hasPrefix("Guide"))
        XCTAssertEqual(guide.document.root.children.count, 8)
        let texts = LibraryDocument.texts(of: guide.document.root).joined(separator: "\n")
        for word in ["Reminders", "Spotlight", "Shortcuts", "Presentation"] {
            XCTAssertTrue(texts.contains(word), word)
        }
        XCTAssertTrue(guide.document.root.tagCounts.keys.allSatisfy {
            ["Important", "Exam", "Remember", "Example", "Definition", "Question", "Unclear"].contains($0)
        })
        XCTAssertEqual(guide.document.connections.count, 1)
    }

    #endif
}
