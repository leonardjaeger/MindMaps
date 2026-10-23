import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M4: Vorlagen, Einlesen der Bibliothek, Suche, Ordner, Papierkorb, Beispieldokumente.
/// Jeder Test arbeitet in einem eigenen temporären Ordner.
final class M4Tests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMapsTests-\(UUID().uuidString)", isDirectory: true)
        try LibraryStore.ensureLibrary(at: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func scan() -> LibraryContents {
        var cache: [URL: LibraryDocument] = [:]
        return LibraryScanner.scan(root, cache: &cache)
    }

    // MARK: - Vorlagen

    func testTemplatesAreValidDocuments() throws {
        XCTAssertEqual(DocumentTemplate.allCases.map(\.title), ["Leer", "Referat", "Lernzettel", "Projektplan"])
        for template in DocumentTemplate.allCases {
            let doc = template.makeDocument()
            XCTAssertEqual(try MindMapCodec.decode(try MindMapCodec.encode(doc)), doc, template.title)
            XCTAssertTrue(ThemeStore.catalog.themes.contains { $0.id == doc.themeID }, "Thema \(doc.themeID) gibt es")
        }
        XCTAssertEqual(DocumentTemplate.blank.makeDocument().root.nodeCount, 1)
        XCTAssertGreaterThan(DocumentTemplate.referat.makeDocument().root.nodeCount, 10)
    }

    // MARK: - Einlesen und Suche

    func testScanFindsDocumentsInNestedFoldersAndIgnoresTrash() throws {
        let a = try LibraryStore.createFolder(named: "A", in: root)
        let b = try LibraryStore.createFolder(named: "B", in: a)
        let c = try LibraryStore.createFolder(named: "C", in: b)
        try LibraryStore.createDocument(DocumentTemplate.referat.makeDocument(), named: "Oben", in: root)
        try LibraryStore.createDocument(DocumentTemplate.lernzettel.makeDocument(), named: "Tief", in: c)
        let weg = try LibraryStore.createDocument(.newDocument(), named: "Weg", in: a)
        try LibraryStore.moveToTrash(weg, libraryRoot: root)

        let contents = scan()
        XCTAssertEqual(Set(contents.documents.map(\.title)), ["Oben", "Tief"], "Papierkorb zählt nicht mit")
        XCTAssertEqual(contents.root.flattened().map(\.folder.name), [root.lastPathComponent, "A", "B", "C"])
        XCTAssertEqual(contents.trash.map(\.name), ["Weg"])
        XCTAssertEqual(contents.trash.first?.originalFolder, "A")
    }

    func testSearchFindsTitleAndDeepNodeTextIgnoringCaseAndAccents() throws {
        var data = DocumentTemplate.lernzettel.makeDocument()
        let deep = data.root.children[0].children[0]
        data.root.updateNode(id: deep.id) { $0.children = [Node(text: "Chlorophyll fängt Licht ein")] }
        try LibraryStore.createDocument(data, named: "Biologie", in: root)
        try LibraryStore.createDocument(.newDocument(), named: "Ökologie", in: root)

        let docs = scan().documents
        let bio = try XCTUnwrap(docs.first { $0.title == "Biologie" })
        XCTAssertEqual(bio.match("chlorophyll"), "Chlorophyll fängt Licht ein", "Tiefer Knoten, andere Schreibweise")
        XCTAssertEqual(bio.match("FAENGT") , nil, "ä ist nicht ae")
        XCTAssertEqual(bio.match("fangt"), "Chlorophyll fängt Licht ein", "Akzente werden ignoriert")
        XCTAssertEqual(docs.first { $0.title == "Ökologie" }?.match("oko"), "Ökologie", "Titel")
        XCTAssertNil(bio.match("   "))
    }

    func testCacheRereadsOnlyChangedDocuments() throws {
        let url = try LibraryStore.createDocument(.newDocument(), named: "Doc", in: root)
        var cache: [URL: LibraryDocument] = [:]
        _ = LibraryScanner.scan(root, cache: &cache)
        XCTAssertEqual(cache.count, 1)

        var changed = MindMapDocumentData.newDocument()
        changed.root.text = "Geändert"
        let json = url.appendingPathComponent(MindMapCodec.documentFileName)
        try MindMapCodec.encode(changed).write(to: json)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: json.path)
        let rescanned = LibraryScanner.scan(root, cache: &cache)
        XCTAssertEqual(rescanned.documents.first?.data.root.text, "Geändert")

        try FileManager.default.removeItem(at: url)
        _ = LibraryScanner.scan(root, cache: &cache)
        XCTAssertTrue(cache.isEmpty, "Gelöschte Dokumente fallen aus dem Zwischenspeicher")
    }

    // MARK: - Ordner, Verschieben, Umbenennen

    func testUniqueNamesMoveAndRename() throws {
        let first = try LibraryStore.createDocument(.newDocument(), named: "Unbenannt", in: root)
        let second = try LibraryStore.createDocument(.newDocument(), named: "Unbenannt", in: root)
        XCTAssertEqual(first.lastPathComponent, "Unbenannt.mindmaps")
        XCTAssertEqual(second.lastPathComponent, "Unbenannt 2.mindmaps")

        let folder = try LibraryStore.createFolder(in: root)
        XCTAssertEqual(folder.lastPathComponent, "Neuer Ordner")
        let moved = try LibraryStore.move(second, to: folder)
        XCTAssertEqual(moved.deletingLastPathComponent().lastPathComponent, "Neuer Ordner")
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))

        let renamed = try LibraryStore.rename(moved, to: "Referat Biologie")
        XCTAssertEqual(renamed.lastPathComponent, "Referat Biologie.mindmaps", "Endung bleibt erhalten")
        XCTAssertThrowsError(try LibraryStore.rename(first, to: "a/b")) { error in
            XCTAssertEqual(error as? LibraryStore.LibraryError, .invalidName)
        }
        let renamedFolder = try LibraryStore.rename(folder, to: "Biologie")
        XCTAssertThrowsError(try LibraryStore.move(renamedFolder, to: renamedFolder)) { error in
            XCTAssertEqual(error as? LibraryStore.LibraryError, .moveIntoItself)
        }
        XCTAssertEqual(Set(scan().documents.map(\.title)), ["Unbenannt", "Referat Biologie"])
    }

    // MARK: - Papierkorb

    func testTrashAndRestoreToOriginalFolder() throws {
        let studium = try LibraryStore.createFolder(named: "Studium", in: root)
        let bio = try LibraryStore.createFolder(named: "Biologie", in: studium)
        let doc = try LibraryStore.createDocument(DocumentTemplate.referat.makeDocument(), named: "Zelle", in: bio)

        let trashed = try LibraryStore.moveToTrash(doc, libraryRoot: root)
        XCTAssertTrue(scan().documents.isEmpty)
        XCTAssertEqual(scan().trash.first?.originalFolder, "Studium/Biologie")

        // Auch wenn der Ordner inzwischen fehlt, wird er beim Wiederherstellen neu angelegt.
        try FileManager.default.removeItem(at: studium)
        let restored = try LibraryStore.restore(trashed, libraryRoot: root)
        XCTAssertEqual(LibraryStore.relativePath(of: restored.deletingLastPathComponent(), in: root), "Studium/Biologie")
        XCTAssertEqual(scan().documents.map(\.title), ["Zelle"])
        XCTAssertTrue(scan().trash.isEmpty)
    }

    /// Fehler aus der M4-Abnahme: In iCloud Drive galten Dateien im Papierkorb als versteckt,
    /// der Papierkorb wirkte leer. Versteckt-Markierung darf die Anzeige nicht verhindern.
    func testTrashListsItemsEvenWhenMarkedHidden() throws {
        let doc = try LibraryStore.createDocument(.newDocument(), named: "Versteckt", in: root)
        var trashed = try LibraryStore.moveToTrash(doc, libraryRoot: root)
        var values = URLResourceValues()
        values.isHidden = true
        try trashed.setResourceValues(values)
        XCTAssertEqual(try trashed.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)

        XCTAssertEqual(scan().trash.map(\.name), ["Versteckt"])
        XCTAssertFalse(scan().trash.contains { $0.name.hasPrefix(".") }, ".herkunft.json bleibt unsichtbar")
    }

    // MARK: - Beispieldokumente

    func testSampleLibraryHasTwentyDocumentsInNestedFolders() throws {
        XCTAssertEqual(SampleLibrary.documentCount, 20)
        let base = try SampleLibrary.create(in: root)
        let contents = scan()
        XCTAssertEqual(contents.documents.count, 20)
        let deepest = contents.root.flattened().map(\.depth).max() ?? 0
        XCTAssertGreaterThanOrEqual(deepest, 3, "Mindestens 3 verschachtelte Ordner")
        let hits = contents.documents.filter { $0.match("Chlorophyll") != nil }
        XCTAssertEqual(hits.map(\.title), ["Lernzettel Photosynthese"])
        XCTAssertEqual(base.lastPathComponent, "Beispiele")
    }
}
