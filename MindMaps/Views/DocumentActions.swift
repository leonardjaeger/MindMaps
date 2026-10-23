import Foundation

/// Alle Bearbeitungsaktionen am Dokument, jeweils als eigener Rückgängig-Schritt.
/// Wird von Werkzeugleiste, Gliederung und Mindmap gemeinsam genutzt.
struct DocumentActions {
    let document: MindMapFile
    let undoManager: UndoManager?

    private var root: Node { document.data.root }

    /// Legt einen leeren Unterknoten an und liefert seine ID.
    @discardableResult
    func addChild(to parentID: UUID?) -> UUID {
        let node = Node(text: "")
        let parent = parentID ?? root.id
        document.apply(L("Knoten hinzufügen"), undoManager: undoManager) { data in
            data.root.addChild(node, to: parent)
        }
        return node.id
    }

    /// Legt einen leeren Knoten direkt nach `id` an (beim Hauptknoten: Unterknoten).
    @discardableResult
    func addSibling(after id: UUID) -> UUID {
        let node = Node(text: "")
        document.apply(L("Knoten hinzufügen"), undoManager: undoManager) { data in
            data.root.addSibling(node, after: id)
        }
        return node.id
    }

    /// Löscht einen Knoten samt Unterknoten und liefert den Knoten, der danach ausgewählt werden soll.
    @discardableResult
    func delete(_ id: UUID) -> UUID? {
        guard id != root.id else { return id }
        let next = root.selectionAfterRemoving(id)
        document.apply(L("Knoten löschen"), undoManager: undoManager) { data in
            data.root.removeNode(id: id)
            // Verbindungen zu gelöschten Knoten fallen mit weg (M7).
            data.pruneConnections()
        }
        return next
    }

    func setText(_ text: String, of id: UUID) {
        document.apply(L("Text ändern"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.text = text }
        }
    }

    /// Hängt einen Knoten (samt Unterknoten) an einen neuen Elternknoten, ans Ende.
    func move(_ id: UUID, to parentID: UUID) {
        guard root.canMove(id, toParent: parentID) else { return }
        document.apply(L("Knoten verschieben"), undoManager: undoManager) { data in
            data.root.moveNode(id: id, toParent: parentID)
        }
    }

    /// Sortiert einen Knoten direkt vor oder nach einem anderen ein (Drag & Drop in der Outline).
    func move(_ id: UUID, beside targetID: UUID, after: Bool) {
        guard root.canMove(id, beside: targetID) else { return }
        document.apply(L("Knoten verschieben"), undoManager: undoManager) { data in
            data.root.moveNode(id, beside: targetID, after: after)
        }
    }

    /// Tab in der Outline: eine Ebene tiefer.
    func indent(_ id: UUID) {
        document.apply(L("Einrücken"), undoManager: undoManager) { data in
            data.root.indentNode(id)
        }
    }

    /// ⇧ Tab in der Outline: eine Ebene höher.
    func outdent(_ id: UUID) {
        document.apply(L("Ausrücken"), undoManager: undoManager) { data in
            data.root.outdentNode(id)
        }
    }

    /// Ein-/Ausklappen. Der Hauptknoten und Knoten ohne Unterknoten bleiben unverändert.
    func toggleCollapsed(_ id: UUID) {
        guard root.canToggleCollapse(id) else { return }
        let collapsed = root.node(withID: id)?.isCollapsed ?? false
        document.apply(collapsed ? L("Aufklappen") : L("Einklappen"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.isCollapsed.toggle() }
        }
    }

    // MARK: - Notizen, Aufgaben, Tags (M6)

    func setNote(_ note: String, of id: UUID) {
        guard root.node(withID: id)?.note != note else { return }
        document.apply(L("Notiz ändern"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.note = note }
        }
    }

    /// Aufgabe an/aus (⇧ ⌘ T).
    func toggleTask(_ id: UUID) {
        let isTask = root.node(withID: id)?.task != nil
        document.apply(isTask ? L("Aufgabe entfernen") : L("Als Aufgabe markieren"), undoManager: undoManager) { data in
            data.root.toggleTask(id)
        }
    }

    /// Abhaken / wieder öffnen (⇧ ⌘ D, Klick aufs Kästchen). Bei Zweigen: alle Aufgaben darunter.
    func toggleDone(_ id: UUID) {
        let done = root.node(withID: id)?.taskStatus == .done
        document.apply(done ? L("Aufgabe öffnen") : L("Aufgabe abhaken"), undoManager: undoManager) { data in
            data.root.toggleDone(id)
        }
    }

    func toggleTag(_ tag: String, on id: UUID) {
        document.apply(L("Tag ändern"), undoManager: undoManager) { data in
            data.root.toggleTag(tag, on: id)
        }
    }

    /// Klappt die Vorfahren auf, damit ein Knoten sichtbar wird (Suchtreffer).
    func reveal(_ id: UUID) {
        guard root.visibleNode(for: id) != id else { return }
        document.apply(L("Aufklappen"), undoManager: undoManager) { data in
            data.root.expandAncestors(of: id)
        }
    }

    @discardableResult
    func replace(in id: UUID, _ query: String, with replacement: String, options: FindOptions) -> Int {
        var copy = root
        let count = copy.replace(in: id, query, with: replacement, options: options)
        guard count > 0 else { return 0 }
        document.apply(L("Ersetzen"), undoManager: undoManager) { data in data.root = copy }
        return count
    }

    @discardableResult
    func replaceAll(_ query: String, with replacement: String, options: FindOptions) -> Int {
        var copy = root
        let count = copy.replaceAll(query, with: replacement, options: options)
        guard count > 0 else { return 0 }
        document.apply(L("Alle ersetzen"), undoManager: undoManager) { data in data.root = copy }
        return count
    }

    // MARK: - Links, Bilder, Formeln, Verbindungen (M7)

    func setLink(_ link: String, of id: UUID) {
        let value = DocumentLink.normalized(link)
        document.apply(value.isEmpty ? L("Link entfernen") : L("Link setzen"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.link = value }
        }
    }

    func setFormula(_ formula: String, of id: UUID) {
        let value = formula.trimmingCharacters(in: .whitespacesAndNewlines)
        document.apply(value.isEmpty ? L("Formel entfernen") : L("Formel ändern"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.formula = value }
        }
    }

    /// Bild einfügen (Datei, Fotos, Drag & Drop). Liefert `false`, wenn die Daten kein Bild sind.
    @discardableResult
    func insertImage(_ contents: Data, into id: UUID) -> Bool {
        guard let prepared = ImageImport.prepare(contents) else { return false }
        let asset = document.addAsset(prepared.data, fileExtension: prepared.fileExtension)
        let image = NodeImage(asset: asset, width: Double(prepared.size.width), height: Double(prepared.size.height))
        document.apply(L("Bild einfügen"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.image = image }
        }
        return true
    }

    func resizeImage(of id: UUID, toWidth width: Double) {
        guard let image = root.node(withID: id)?.image else { return }
        let resized = image.resized(toWidth: width)
        guard resized != image else { return }
        document.apply(L("Bildgröße ändern"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.image = resized }
        }
    }

    func removeImage(of id: UUID) {
        document.apply(L("Bild entfernen"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.image = nil }
        }
    }

    /// Neue Querverbindung; liefert ihre ID (oder `nil`, wenn sie nicht möglich oder schon da ist).
    @discardableResult
    func connect(_ from: UUID, to: UUID) -> UUID? {
        let data = document.data
        guard from != to, data.root.contains(from), data.root.contains(to),
              !data.hasConnection(from: from, to: to) else { return nil }
        let connection = Connection(from: from, to: to)
        document.apply(L("Verbindung hinzufügen"), undoManager: undoManager) { data in
            data.connections.append(connection)
        }
        return connection.id
    }

    func removeConnection(_ id: UUID) {
        document.apply(L("Verbindung löschen"), undoManager: undoManager) { data in
            data.connections.removeAll { $0.id == id }
        }
    }

    func setConnectionLabel(_ label: String, of id: UUID) {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        document.apply(L("Beschriftung ändern"), undoManager: undoManager) { data in
            if let index = data.connections.firstIndex(where: { $0.id == id }) { data.connections[index].label = value }
        }
    }

    func setConnectionBend(_ bend: CGSize?, of id: UUID) {
        document.apply(L("Verbindung biegen"), undoManager: undoManager) { data in
            if let index = data.connections.firstIndex(where: { $0.id == id }) {
                data.connections[index].bendX = bend.map { Double($0.width.rounded()) }
                data.connections[index].bendY = bend.map { Double($0.height.rounded()) }
            }
        }
    }

    /// Eingebautes Thema wählen (eigene Anpassungen fallen weg; Rückgängig holt sie zurück).
    func setTheme(_ themeID: String) {
        if !ThemeStore.isBuiltIn(themeID), let own = ThemeLibrary.themes().first(where: { $0.id == themeID }) {
            applyTheme(own)
            return
        }
        document.apply(L("Thema ändern"), undoManager: undoManager) { data in
            data.themeID = themeID
            data.customTheme = nil
        }
    }

    // MARK: - Gestaltung (M8)

    /// Thema anwenden. Eigene Themen werden im Dokument mitgespeichert.
    func applyTheme(_ theme: Theme) {
        document.apply(L("Thema ändern"), undoManager: undoManager) { data in
            data.themeID = theme.id
            data.customTheme = ThemeStore.isBuiltIn(theme.id) && ThemeStore.original(withID: theme.id) == theme ? nil : theme
        }
    }

    /// Thema des Dokuments anpassen (Farben, Form, Schrift …).
    func updateTheme(_ actionName: String = L("Thema anpassen"), _ change: (inout Theme) -> Void) {
        var theme = ThemeStore.theme(for: document.data)
        change(&theme)
        document.apply(actionName, undoManager: undoManager) { data in
            // Eingebaute Themen ohne Änderung brauchen keine Kopie im Dokument, eigene immer.
            let unchangedBuiltIn = ThemeStore.isBuiltIn(data.themeID) && ThemeStore.original(withID: data.themeID) == theme
            data.customTheme = unchangedBuiltIn ? nil : theme
        }
    }

    /// Anpassungen am Thema verwerfen: zurück zum Original (eingebaut oder aus „Eigene Themen“).
    func revertTheme() {
        let original = ThemeStore.original(withID: document.data.themeID)
        document.apply(L("Anpassungen verwerfen"), undoManager: undoManager) { data in
            data.customTheme = ThemeStore.isBuiltIn(data.themeID) ? nil : (original ?? data.customTheme)
        }
    }

    func updateMapStyle(_ actionName: String, _ change: (inout MapStyle) -> Void) {
        document.apply(actionName, undoManager: undoManager) { data in
            change(&data.style)
        }
    }

    /// Anderes Layout: übliche Ausrichtung dazu, von Hand verschobene Knoten springen zurück.
    func setLayout(_ layout: MapStyle.Layout) {
        guard document.data.style.layout != layout else { return }
        document.apply(L("Layout ändern"), undoManager: undoManager) { data in
            data.style.layout = layout
            data.style.sides = MapStyle.defaultSides(for: layout)
            data.root.clearOffsets()
        }
    }

    func updateNodeStyle(_ id: UUID, _ actionName: String = L("Stil ändern"), _ change: (inout NodeStyle) -> Void) {
        document.apply(actionName, undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in
                var style = node.style ?? NodeStyle()
                change(&style)
                node.style = style.isEmpty ? nil : style
            }
        }
    }

    func setShape(_ shape: Theme.NodeShape?, of id: UUID) {
        updateNodeStyle(id, L("Form ändern")) { $0.shape = shape }
    }

    /// Stil einsetzen (⌘ R) bzw. zurücksetzen (`nil`).
    func setNodeStyle(_ style: NodeStyle?, of id: UUID, actionName: String = L("Stil einsetzen")) {
        document.apply(actionName, undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.style = (style?.isEmpty ?? true) ? nil : style }
        }
    }

    /// Knoten von Hand verschieben (Unterknoten wandern mit).
    func offsetNode(_ id: UUID, by delta: CGSize) {
        guard id != root.id, delta.width != 0 || delta.height != 0 else { return }
        document.apply(L("Knoten verschieben"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in
                let old = node.offset ?? NodeOffset(x: 0, y: 0)
                let new = NodeOffset(x: (old.x + Double(delta.width)).rounded(), y: (old.y + Double(delta.height)).rounded())
                node.offset = new.isZero ? nil : new
            }
        }
    }

    func resetPosition(of id: UUID) {
        document.apply(L("Position zurücksetzen"), undoManager: undoManager) { data in
            data.root.updateNode(id: id) { node in node.offset = nil }
        }
    }

    func resetAllPositions() {
        document.apply(L("Alle Positionen zurücksetzen"), undoManager: undoManager) { data in
            data.root.clearOffsets()
        }
    }

    // MARK: - Erinnerungen (M9)

    /// Abgleich mit einer Liste in Erinnerungen ein- (`link`) oder ausschalten (`nil`).
    func setRemindersLink(_ link: RemindersLink?, actionName: String? = nil) {
        let name = actionName ?? (link == nil ? L("Abgleich mit Erinnerungen beenden") : L("Mit Erinnerungen abgleichen"))
        document.apply(name, undoManager: undoManager) { data in
            data.reminders = link
        }
    }

    // MARK: - Verlauf (M10)

    /// Holt eine ganze frühere Fassung zurück (ein Schritt, mit ⌘Z rückgängig).
    func restoreVersion(_ old: MindMapDocumentData, date: Date) {
        let when = date.formatted(date: .abbreviated, time: .shortened)
        document.apply(L("Fassung vom %@ wiederherstellen", when), undoManager: undoManager) { data in
            DocumentHistory.restoreAll(from: old, into: &data)
        }
    }

    /// Holt einen Zweig aus einer früheren Fassung zurück; der Rest der Map bleibt.
    /// Liefert die ID des Zweigs in der aktuellen Map.
    @discardableResult
    func restoreBranch(_ id: UUID, from old: MindMapDocumentData) -> UUID? {
        var restored: UUID?
        document.apply(L("Zweig wiederherstellen"), undoManager: undoManager) { data in
            restored = DocumentHistory.restoreBranch(id, from: old, into: &data)
        }
        return restored
    }
}
