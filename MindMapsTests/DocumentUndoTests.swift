import XCTest
@testable import MindMaps

/// Rückgängig/Wiederholen über das Dokument (M2-Abnahme: „20× Rückgängig stellt den Ausgangszustand exakt wieder her“).
final class DocumentUndoTests: XCTestCase {

    func testTwentyUndosRestoreTheOriginalAndRedoRestoresTheResult() {
        let document = MindMapFile(data: CoreTests.referenceDocument())
        let original = document.data
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)

        /// Jede Aktion ist ein eigener Schritt, wie in der App ein Tastendruck.
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        var root: Node { document.data.root }

        var added: [UUID] = []
        for i in 0..<5 {                                                         // 10 Schritte
            step { added.append(actions.addChild(to: root.id)) }
            step { actions.setText("Neu \(i)", of: added[i]) }
        }
        step { actions.move(root.children[0].children[0].id, to: root.children[1].id) }  // 11
        step { _ = actions.delete(root.children[0].id) }                                  // 12
        step { actions.toggleCollapsed(root.children[0].id) }                             // 13
        step { actions.setTheme("neon") }                                                 // 14
        for _ in 0..<4 {                                                                  // 15–18
            step { _ = actions.addSibling(after: added[0]) }
        }
        step { actions.setText("Anderer Titel", of: root.id) }                           // 19
        step { actions.move(added[1], to: added[2]) }                                     // 20
        let result = document.data
        XCTAssertNotEqual(result, original)

        var undos = 0
        while undo.canUndo {
            undo.undo()
            undos += 1
        }
        XCTAssertEqual(undos, 20)
        XCTAssertEqual(document.data, original, "20× Rückgängig ergibt exakt den Ausgangszustand")

        while undo.canRedo { undo.redo() }
        XCTAssertEqual(document.data, result, "Wiederholen stellt alles wieder her")
    }

    /// Ohne manuelle Gruppe: Eine leere Gruppe würde der UndoManager sonst selbst als Schritt zählen.
    /// Mit `groupsByEvent` (Standard) öffnet er erst dann eine Gruppe, wenn wirklich etwas registriert wird.
    func testUnchangedActionsCreateNoUndoStep() {
        let document = MindMapFile()
        let undo = UndoManager()
        let actions = DocumentActions(document: document, undoManager: undo)

        actions.setText(document.data.root.text, of: document.data.root.id)
        actions.setTheme(document.data.themeID)
        actions.move(document.data.root.id, to: document.data.root.id)
        XCTAssertFalse(undo.canUndo, "Aktionen ohne Änderung dürfen keinen Rückgängig-Schritt anlegen")

        actions.setTheme("neon")
        XCTAssertTrue(undo.canUndo, "Gegenprobe: Eine echte Änderung legt einen Schritt an")
    }

    /// M3: Einrücken, Ausrücken, Umsortieren und Einklappen sind je ein Rückgängig-Schritt.
    func testOutlineActionsAreUndoable() {
        let document = MindMapFile(data: CoreTests.referenceDocument())
        let original = document.data
        let undo = UndoManager()
        undo.groupsByEvent = false
        let actions = DocumentActions(document: document, undoManager: undo)
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        var root: Node { document.data.root }

        let thema = root.children[0].children[1]
        step { actions.indent(thema.id) }
        step { actions.outdent(thema.id) }
        step { actions.outdent(thema.id) }
        step { actions.move(root.children[3].id, beside: root.children[0].id, after: false) }
        step { actions.toggleCollapsed(root.children[1].id) }
        XCTAssertNotEqual(document.data, original)

        var undos = 0
        while undo.canUndo {
            undo.undo()
            undos += 1
        }
        XCTAssertEqual(undos, 5)
        XCTAssertEqual(document.data, original)
    }
}
