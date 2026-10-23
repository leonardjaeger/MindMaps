import AppKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Meldet die Dokumente der Bibliothek an Spotlight (M9) – mit allen Knotentexten und Notizen.
/// ⌘ Leertaste findet eine Mindmap dann auch über ein Wort, das nur in einem Knoten steht.
@MainActor
enum SpotlightIndexer {
    nonisolated static let domain = "de.leonardjaeger.MindMaps.documents"
    /// Einstellung „Mindmaps in Spotlight finden“ (Einstellungen › Bibliothek).
    nonisolated static let enabledKey = "spotlightEnabled"

    /// Pfad → Änderungsdatum der gemeldeten Dokumente.
    private static var indexed: [String: Date] = [:]
    /// Beim ersten Durchlauf nach dem Start wird der alte Stand verworfen und alles neu gemeldet.
    private static var didStart = false

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
    }

    /// Nach jedem Einlesen der Bibliothek: neue und geänderte Dokumente melden, verschwundene entfernen.
    static func update(_ documents: [LibraryDocument]) {
        guard isEnabled, CSSearchableIndex.isIndexingAvailable() else { return }
        let index = CSSearchableIndex.default()
        var current: [String: Date] = [:]
        var items: [CSSearchableItem] = []
        for document in documents {
            let id = identifier(for: document.url)
            current[id] = document.modified
            if didStart, indexed[id] == document.modified { continue }
            items.append(item(for: document, id: id))
        }
        if !didStart {
            didStart = true
            indexed = current
            // Erst den alten Stand löschen, dann neu melden (die Liste wird nur hier weitergereicht).
            nonisolated(unsafe) let pending = items
            index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
                CSSearchableIndex.default().indexSearchableItems(pending)
            }
            return
        }
        let removed = indexed.keys.filter { current[$0] == nil }
        indexed = current
        if !removed.isEmpty { index.deleteSearchableItems(withIdentifiers: removed) }
        if !items.isEmpty { index.indexSearchableItems(items) }
    }

    /// Alles aus Spotlight entfernen (Einstellung ausgeschaltet).
    static func removeAll() {
        indexed = [:]
        didStart = false
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    static func identifier(for url: URL) -> String { url.standardizedFileURL.path }

    private static func item(for document: LibraryDocument, id: String) -> CSSearchableItem {
        let content = SpotlightContent.make(title: document.title, data: document.data)
        let attributes = CSSearchableItemAttributeSet(contentType: .mindMapsDocument)
        attributes.title = content.title
        attributes.displayName = content.title
        attributes.textContent = content.text
        attributes.contentDescription = content.summary
        attributes.keywords = content.keywords
        attributes.contentModificationDate = document.modified
        attributes.contentURL = document.url
        let thumbnail = document.url.appendingPathComponent(MindMapFile.quickLookFolderName)
            .appendingPathComponent("Thumbnail.png")
        if FileManager.default.fileExists(atPath: thumbnail.path) { attributes.thumbnailURL = thumbnail }
        let item = CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
        item.expirationDate = .distantFuture
        return item
    }

    /// Ein Spotlight-Treffer wurde angeklickt: Dokument öffnen.
    @discardableResult
    static func open(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return false }
        let url = URL(fileURLWithPath: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id])
            return false
        }
        MindMapCatalog.open(url)
        return true
    }
}
