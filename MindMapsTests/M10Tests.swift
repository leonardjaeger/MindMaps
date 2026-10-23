import XCTest
#if canImport(MindMapsCore)
@testable import MindMapsCore
#else
@testable import MindMaps
#endif

/// Tests für M10: Dokumentverlauf.
final class M10Tests: XCTestCase {

    // MARK: - Hilfen

    private static let now = Date(timeIntervalSince1970: 1_790_400_000)   // Ende September 2026

    private static func entry(_ date: Date, _ fingerprint: String = UUID().uuidString) -> HistoryEntry {
        HistoryEntry(file: DocumentHistory.baseName(for: date), date: date, nodeCount: 1,
                     fingerprint: fingerprint, assets: [])
    }

    /// Referat › Einleitung (Einstieg, Ziel) · Hauptteil (A, B) · Schluss, mit einer Verbindung Ziel → B.
    private static func sample() -> (data: MindMapDocumentData, ids: [String: UUID]) {
        let einstieg = Node(text: "Einstieg"), ziel = Node(text: "Ziel")
        let a = Node(text: "A"), b = Node(text: "B")
        let einleitung = Node(text: "Einleitung", children: [einstieg, ziel])
        let hauptteil = Node(text: "Hauptteil", children: [a, b])
        let schluss = Node(text: "Schluss")
        var data = MindMapDocumentData(root: Node(text: "Referat", children: [einleitung, hauptteil, schluss]))
        data.connections = [Connection(from: ziel.id, to: b.id, label: "führt zu")]
        return (data, ["einstieg": einstieg.id, "ziel": ziel.id, "a": a.id, "b": b.id, "einleitung": einleitung.id,
                       "hauptteil": hauptteil.id, "schluss": schluss.id])
    }

    // MARK: - Aufnehmen

    func testFingerprintIgnoresTheSaveDate() {
        var (data, ids) = Self.sample()
        let first = DocumentHistory.fingerprint(of: data)
        data.modifiedAt = Date(timeIntervalSince1970: 123)
        XCTAssertEqual(DocumentHistory.fingerprint(of: data), first)
        data.root.updateNode(id: ids["a"]!) { $0.text = "A2" }
        XCTAssertNotEqual(DocumentHistory.fingerprint(of: data), first)
    }

    func testRecordAtMostEveryTenMinutesAndOnlyWhenChanged() {
        XCTAssertTrue(DocumentHistory.shouldRecord(fingerprint: "x", at: Self.now, after: []))
        let last = Self.entry(Self.now.addingTimeInterval(-9 * 60), "x")
        XCTAssertFalse(DocumentHistory.shouldRecord(fingerprint: "y", at: Self.now, after: [last]), "zu früh")
        let older = Self.entry(Self.now.addingTimeInterval(-11 * 60), "x")
        XCTAssertTrue(DocumentHistory.shouldRecord(fingerprint: "y", at: Self.now, after: [older]))
        XCTAssertFalse(DocumentHistory.shouldRecord(fingerprint: "x", at: Self.now, after: [older]), "unverändert")

        XCTAssertEqual(DocumentHistory.baseName(for: Date(timeIntervalSince1970: 0)), "19700101-000000")
        XCTAssertEqual(DocumentHistory.baseName(for: Self.now), "20260926-052000")
    }

    func testThinningKeepsDenseRecentAndSparseOldStates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        // 90 Tage lang jeden Tag 8 Stunden Arbeit, alle 10 Minuten ein Zwischenstand.
        var entries: [HistoryEntry] = []
        for day in 0..<90 {
            for step in 0..<48 {
                let date = Self.now.addingTimeInterval(-Double(day) * 86_400 - 8 * 3600 + Double(step) * 600)
                if date <= Self.now { entries.append(Self.entry(date)) }
            }
        }
        let kept = DocumentHistory.thinned(entries, now: Self.now, calendar: calendar)
        XCTAssertEqual(kept.first?.date, entries.map(\.date).max(), "der neueste bleibt immer")
        XCTAssertEqual(kept.map(\.date), kept.map(\.date).sorted(by: >), "neueste zuerst")

        let lastDay = kept.filter { Self.now.timeIntervalSince($0.date) < 86_400 }
        XCTAssertEqual(lastDay.count, 48, "letzte 24 Stunden: alle 10 Minuten")
        let month = kept.filter { (86_400..<30 * 86_400).contains(Self.now.timeIntervalSince($0.date)) }
        let days = Set(month.map { calendar.startOfDay(for: $0.date) })
        XCTAssertEqual(month.count, days.count, "höchstens einer pro Tag")
        XCTAssertLessThanOrEqual(month.count, 30)
        let older = kept.filter { Self.now.timeIntervalSince($0.date) >= 30 * 86_400 }
        XCTAssertLessThanOrEqual(older.count, 10, "danach einer pro Woche")
        XCTAssertGreaterThanOrEqual(older.count, 8)
        XCTAssertLessThan(kept.count, 100)

        // Ausdünnen ist stabil: nochmal ausdünnen ändert nichts.
        XCTAssertEqual(DocumentHistory.thinned(kept, now: Self.now, calendar: calendar), kept)
        // Obergrenze
        let many = (0..<400).map { Self.entry(Self.now.addingTimeInterval(-Double($0) * 7 * 86_400 - 31 * 86_400)) }
        XCTAssertEqual(DocumentHistory.thinned(many, now: Self.now, calendar: calendar).count,
                       DocumentHistory.maximumEntries)
    }

    func testIndexRoundTrip() throws {
        let entries = [Self.entry(Self.now), Self.entry(Self.now.addingTimeInterval(-3600))]
        let decoded = DocumentHistory.decodeIndex(try DocumentHistory.encodeIndex(entries.reversed()))
        XCTAssertEqual(decoded, entries, "neueste zuerst")
        XCTAssertEqual(DocumentHistory.decodeIndex(Data("kaputt".utf8)), [])
    }

    // MARK: - Wiederherstellen

    func testDeletedBranchComesBackAtItsOldPlace() throws {
        let (old, ids) = Self.sample()
        var current = old
        current.root.removeNode(id: ids["hauptteil"]!)
        current.pruneConnections()
        current.root.updateNode(id: ids["schluss"]!) { $0.text = "Fazit" }   // spätere Änderung bleibt
        current.root.addChild(Node(text: "Neu"), to: current.root.id)

        let restored = DocumentHistory.restoreBranch(ids["hauptteil"]!, from: old, into: &current)
        XCTAssertEqual(restored, ids["hauptteil"])
        XCTAssertEqual(current.root.children.map(\.text), ["Einleitung", "Hauptteil", "Fazit", "Neu"])
        XCTAssertEqual(current.root.node(withID: ids["hauptteil"]!)?.children.map(\.text), ["A", "B"])
        XCTAssertEqual(current.connections.count, 1, "Verbindung Ziel → B ist wieder da")
        XCTAssertEqual(current.connections.first?.to, ids["b"])
        XCTAssertEqual(DocumentHistory.removedSince(old.root, current: current.root), [])
    }

    func testExistingBranchIsReplacedAndMovedNodesAreCopied() throws {
        let (old, ids) = Self.sample()
        var current = old
        // A wurde nach „Schluss“ verschoben, B umbenannt, Hauptteil bekam einen neuen Knoten.
        current.root.moveNode(id: ids["a"]!, toParent: ids["schluss"]!)
        current.root.updateNode(id: ids["b"]!) { $0.text = "B geändert" }
        current.root.addChild(Node(text: "C"), to: ids["hauptteil"]!)

        let fresh = UUID()
        DocumentHistory.restoreBranch(ids["hauptteil"]!, from: old, into: &current, newID: { fresh })
        let hauptteil = try XCTUnwrap(current.root.node(withID: ids["hauptteil"]!))
        XCTAssertEqual(hauptteil.children.map(\.text), ["A", "B"])
        XCTAssertEqual(hauptteil.children[0].id, fresh, "A steht auch unter „Schluss“ – deshalb eine Kopie")
        XCTAssertEqual(current.root.node(withID: ids["schluss"]!)?.children.map(\.id), [ids["a"]!])
        XCTAssertEqual(current.root.subtreeIDs.count, current.root.nodeCount, "keine doppelten IDs")
    }

    func testBranchUnderDeletedParentGoesToNearestAncestor() {
        let (old, ids) = Self.sample()
        var current = old
        current.root.removeNode(id: ids["einleitung"]!)
        current.pruneConnections()
        DocumentHistory.restoreBranch(ids["ziel"]!, from: old, into: &current)
        XCTAssertEqual(current.root.parentID(of: ids["ziel"]!), current.root.id)
        XCTAssertEqual(current.connections.count, 1)
        XCTAssertNil(DocumentHistory.restoreBranch(UUID(), from: old, into: &current))
    }

    func testWholeVersionComesBackButKeepsRemindersLink() {
        let (old, ids) = Self.sample()
        var current = old
        current.root.removeNode(id: ids["einleitung"]!)
        current.themeID = "neon"
        current.reminders = RemindersLink(listID: "L1", listTitle: "Referat")
        DocumentHistory.restoreAll(from: old, into: &current)
        XCTAssertEqual(current.root, old.root)
        XCTAssertEqual(current.themeID, old.themeID)
        XCTAssertEqual(current.connections, old.connections)
        XCTAssertEqual(current.reminders?.listID, "L1")

        // Über die Wurzel ist das dasselbe.
        var viaRoot = current
        viaRoot.root.children.removeAll()
        XCTAssertEqual(DocumentHistory.restoreBranch(old.root.id, from: old, into: &viaRoot), old.root.id)
        XCTAssertEqual(viaRoot.root, old.root)
    }

    #if canImport(AppKit)

    // MARK: - Nur auf dem Mac: Dokument, Paket, Rückgängig

    /// Kleines PNG (1 × 1) für Bilder im Paket.
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    func testHistoryIsRecordedOnSaveAndSurvivesThePackage() throws {
        let (data, ids) = Self.sample()
        let document = MindMapFile(data: data)
        let start = Date()
        document.recordHistory(now: start)
        XCTAssertEqual(document.history.entries.count, 1)
        document.recordHistory(now: start.addingTimeInterval(20 * 60))
        XCTAssertEqual(document.history.entries.count, 1, "unverändert – kein neuer Zwischenstand")

        DocumentActions(document: document, undoManager: nil).setText("Neu", of: ids["a"]!)
        document.recordHistory(now: start.addingTimeInterval(5 * 60))
        XCTAssertEqual(document.history.entries.count, 1, "keine 10 Minuten seit dem letzten")
        document.recordHistory(now: start.addingTimeInterval(11 * 60))
        XCTAssertEqual(document.history.entries.count, 2)

        let package = try MindMapFile.makePackage(document.data, assets: document.assets, preview: nil,
                                                  history: document.history)
        XCTAssertNotNil(package.fileWrappers?[DocumentHistory.folderName]?.fileWrappers?[DocumentHistory.indexFileName])
        let read = MindMapFile.readHistory(package)
        XCTAssertEqual(read, document.history)
        let oldest = try XCTUnwrap(read.entries.last)
        XCTAssertEqual(read.document(oldest)?.root, data.root)
        XCTAssertEqual(read.document(read.entries[0])?.root.node(withID: ids["a"]!)?.text, "Neu")
        XCTAssertTrue(MindMapFile.readHistory(try MindMapFile.makePackage(data, assets: [:], preview: nil)).entries.isEmpty)
    }

    func testImagesOfOldVersionsStayInThePackage() throws {
        let (data, ids) = Self.sample()
        let document = MindMapFile(data: data)
        let actions = DocumentActions(document: document, undoManager: nil)
        XCTAssertTrue(actions.insertImage(Self.png, into: ids["a"]!))
        let asset = try XCTUnwrap(document.data.root.node(withID: ids["a"]!)?.image?.asset)
        let start = Date()
        document.recordHistory(now: start)

        // Knoten mit Bild löschen – das Bild bleibt, weil der Verlauf noch darauf verweist.
        actions.delete(ids["hauptteil"]!)
        document.recordHistory(now: start.addingTimeInterval(15 * 60))
        let package = try MindMapFile.makePackage(document.data, assets: document.assets, preview: nil,
                                                  history: document.history)
        let reopened = try MindMapFile.readPackage(package)
        XCTAssertNotNil(reopened.assets[asset], "Bild der alten Fassung ist noch im Paket")

        // Ohne Verlauf wäre es weg (wie bisher).
        let plain = try MindMapFile.readPackage(try MindMapFile.makePackage(document.data, assets: document.assets,
                                                                            preview: nil))
        XCTAssertNil(plain.assets[asset])

        // Fassung zurückholen: Das Bild ist wieder zu sehen.
        let restored = MindMapFile(data: reopened.data, assets: reopened.assets,
                                   history: MindMapFile.readHistory(package))
        let old = try XCTUnwrap(restored.history.entries.last.flatMap(restored.historyDocument))
        DocumentActions(document: restored, undoManager: nil).restoreBranch(ids["hauptteil"]!, from: old)
        XCTAssertEqual(restored.data.root.node(withID: ids["a"]!)?.image?.asset, asset)
        XCTAssertNotNil(restored.assets[asset])
    }

    /// M10-Abnahme: Fassung von gestern und gelöschten Zweig zurückholen – beides mit ⌘Z rückgängig.
    func testRestoreYesterdaysVersionAndADeletedBranchWithUndo() throws {
        let (data, ids) = Self.sample()
        let document = MindMapFile(data: data)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)
        func step(_ body: () -> Void) { undo.beginUndoGrouping(); body(); undo.endUndoGrouping() }

        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        document.recordHistory(now: yesterday)
        step { _ = actions.delete(ids["hauptteil"]!) }
        step { actions.setText("Fazit", of: ids["schluss"]!) }
        document.recordHistory(now: now)
        let today = document.data
        XCTAssertEqual(document.history.entries.count, 2)

        let entry = try XCTUnwrap(document.history.entries.first { Calendar.current.isDateInYesterday($0.date) })
        XCTAssertEqual(HistoryView.dayTitle(Calendar.current.startOfDay(for: entry.date)), "Gestern")
        XCTAssertEqual(HistoryView.days(document.history.entries).count, 2)
        let old = try XCTUnwrap(document.historyDocument(entry))
        XCTAssertEqual(DocumentHistory.removedSince(old.root, current: today.root).count, 3, "Hauptteil, A, B")

        // Nur den Zweig: „Fazit“ bleibt.
        var branch: UUID?
        step { branch = actions.restoreBranch(ids["hauptteil"]!, from: old) }
        XCTAssertEqual(branch, ids["hauptteil"])
        XCTAssertEqual(document.data.root.children.map(\.text), ["Einleitung", "Hauptteil", "Fazit"])
        XCTAssertEqual(document.data.connections.count, 1)
        XCTAssertEqual(undo.undoActionName, "Zweig wiederherstellen")
        undo.undo()
        XCTAssertEqual(document.data, today, "⌘Z nimmt den Zweig wieder weg")

        // Die ganze Fassung von gestern.
        step { actions.restoreVersion(old, date: entry.date) }
        XCTAssertEqual(document.data.root, data.root)
        XCTAssertTrue(undo.undoActionName.hasPrefix("Fassung vom"))
        undo.undo()
        XCTAssertEqual(document.data, today, "⌘Z holt den Stand von heute zurück")
        undo.redo()
        XCTAssertEqual(document.data.root, data.root)
    }

    /// M10-Abnahme: Nach 30 Tagen Arbeit (alle 10 Minuten gesichert) bleibt die Datei klein.
    func testThirtyDaysOfWorkKeepTheFileSmall() throws {
        let document = MindMapFile(data: LargeSample.document(nodeCount: 300))
        let start = Date().addingTimeInterval(-30 * 86_400)
        var saves = 0
        for day in 0..<30 {
            for step in 0..<48 {           // 8 Stunden am Tag
                let now = start.addingTimeInterval(Double(day) * 86_400 + Double(step) * 600)
                let branches = document.data.root.children
                let target = branches[(day + step) % branches.count].id
                DocumentActions(document: document, undoManager: nil).setText("Stand \(day)-\(step)", of: target)
                if step % 6 == 0 {
                    DocumentActions(document: document, undoManager: nil).addChild(to: target)
                }
                document.recordHistory(now: now)
                saves += 1
            }
        }
        let history = document.history
        let json = try MindMapCodec.encode(document.data).count
        let package = try MindMapFile.makePackage(document.data, assets: document.assets, preview: nil,
                                                  history: history)
        func size(_ wrapper: FileWrapper) -> Int {
            wrapper.isDirectory ? (wrapper.fileWrappers ?? [:]).values.reduce(0) { $0 + size($1) }
                                : wrapper.regularFileContents?.count ?? 0
        }
        let total = size(package)
        print("M10 – \(saves) Sicherungen, \(history.entries.count) Zwischenstände, Verlauf \(history.byteCount / 1024) KB, "
              + "Dokument \(json / 1024) KB, Paket \(total / 1024) KB")
        XCTAssertLessThanOrEqual(history.entries.count, 48 + 30, "24 Stunden dicht, danach einer pro Tag")
        XCTAssertLessThan(history.byteCount, 20 * json, "komprimiert: weniger als 20 Dokumente groß")
        XCTAssertLessThan(total, 5 * 1024 * 1024, "Paket unter 5 MB")
        // Alles lässt sich noch lesen.
        for entry in history.entries { XCTAssertNotNil(history.document(entry)) }
    }

    #endif
}
