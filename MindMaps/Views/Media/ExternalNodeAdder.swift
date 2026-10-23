import SwiftUI
import AppKit

/// Legt Knoten aus Anlegen-Links an (`mindmaps://add?…`, 1.3 – Gegenstück zu M30 in MintMarkPDF).
///
/// Regel 13 („Links lösen nie still etwas aus“): Aus MintMarkPDF wird direkt angelegt, aber sichtbar –
/// Fenster nach vorn, neuer Knoten ausgewählt, Hinweis mit „Rückgängig“. Von jeder anderen App
/// (oder unbekanntem Absender) fragt MindMaps vorher nach.
/// Regel 14: Titel, Notiz, Link und Pfad werden nie protokolliert.
@MainActor
enum ExternalNodeAdder {
    nonisolated static let mintMarkBundleID = "de.leonardjaeger.MintMarkPDF"
    /// So lange wird nach dem Öffnen auf das Fenster der Mindmap gewartet.
    static let openTimeout: TimeInterval = 15
    /// Länge des Titels im Hinweis über der Map.
    static let bannerTitleLength = 40

    static func handle(_ link: String, sender: String?) {
        NSApp.activate()
        guard let request = ExternalNodeRequest.parse(link) else {
            showAlert(L("Der Link zum Anlegen eines Knotens ist ungültig."),
                      info: L("Er ist unvollständig, zu lang oder stammt aus einer neueren Fassung von MintMarkPDF. Es wurde nichts geändert."))
            return
        }
        guard FileManager.default.fileExists(atPath: request.file.path) else {
            showAlert(L("Die Mindmap wurde nicht gefunden."), info: request.file.path)
            return
        }
        let fromMintMark = sender == mintMarkBundleID
        if !fromMintMark && !confirm(request) { return }
        Task { await add(request, fromMintMark: fromMintMark) }
    }

    /// Hängt den Knoten als einen Rückgängig-Schritt an (ohne Oberfläche – auch für Tests).
    @discardableResult
    static func insert(_ request: ExternalNodeRequest, into document: MindMapFile, undoManager: UndoManager?,
                       actionName: String = L("Knoten aus MintMarkPDF")) -> ExternalNodeRequest.Placement {
        var placement: ExternalNodeRequest.Placement?
        document.apply(actionName, undoManager: undoManager) { data in
            placement = request.insert(into: &data)
        }
        // `apply` ruft die Änderung immer genau einmal auf.
        return placement ?? ExternalNodeRequest.Placement(nodeID: document.data.root.id, parentMissing: false)
    }

    // MARK: - Ablauf

    private static func add(_ request: ExternalNodeRequest, fromMintMark: Bool) async {
        // Öffnet die Mindmap oder holt ihr Fenster nach vorn, wenn sie schon offen ist. Nicht auf den Abschluss
        // warten: Beim Start von MindMaps über den Link meldet ihn das Öffnen nicht zurück (Machbarkeitstest
        // 12.10.2026) – entscheidend ist, dass das Fenster der Mindmap erscheint.
        let failed = OpenFailure()
        NSDocumentController.shared.openDocument(withContentsOf: request.file, display: true) { _, _, error in
            if error != nil { failed.occurred = true }
        }
        let window = await waitForWindow(request.file, failed: { failed.occurred })
        AppDelegate.log.info("Anlegen: Fenster gefunden: \(window != nil, privacy: .public)")
        guard let window else {
            AppDelegate.log.info("Anlegen: Fenster nicht gefunden")
            // Nichts in die Datei schreiben: Geändert wird nur ein offenes Dokument (mit Rückgängig).
            showAlert(L("Die Mindmap ließ sich nicht öffnen."),
                      info: L("Der Knoten wurde nicht angelegt. Öffne die Mindmap in MindMaps und versuche es noch einmal."))
            return
        }
        let url = window.url
        let entry = window.entry
        let actionName = fromMintMark ? L("Knoten aus MintMarkPDF") : L("Knoten aus einem Link")
        let placement = insert(request, into: entry.document, undoManager: entry.undoManager, actionName: actionName)
        AppDelegate.log.info("Anlegen: Knoten angelegt (Elternknoten fehlte: \(placement.parentMissing, privacy: .public))")

        let title = ExternalNodeRequest.shortened(request.title, to: bannerTitleLength)
        let message: String
        if placement.parentMissing {
            message = L("Knoten „%@“ unter dem Hauptknoten angelegt – der gewählte Knoten existiert nicht mehr.", title)
        } else if fromMintMark {
            message = L("Knoten „%@“ aus MintMarkPDF angelegt", title)
        } else {
            message = L("Knoten „%@“ aus einem Link angelegt", title)
        }
        ExternalNodeNotices.shared.post(ExternalNodeNotices.Notice(nodeID: placement.nodeID, message: message,
                                                                    stateAfter: entry.document.data,
                                                                    actionName: actionName),
                                        for: url)
        // Neuen Knoten auswählen und ins Bild holen (wie Spotlight-Treffer und Aufgaben aus der Bibliothek).
        PendingSelection.set(placement.nodeID, for: url)
        NSApp.activate()
    }

    /// Merkt sich, ob das Öffnen fehlgeschlagen ist (dann nicht bis zum Zeitlimit warten).
    private final class OpenFailure: @unchecked Sendable {
        var occurred = false
    }

    /// Wartet kurz, bis das Fenster der Mindmap angemeldet ist (`OpenDocuments`, siehe EditorView).
    /// Liefert die URL, unter der das Fenster sie kennt.
    private static func waitForWindow(_ file: URL, failed: () -> Bool) async -> (url: URL, entry: OpenDocuments.Entry)? {
        let candidates = [file, file.resolvingSymlinksInPath()]
        let deadline = Date().addingTimeInterval(openTimeout)
        while true {
            // Erst mit Rückgängig-Verlauf: Ein Knoten aus einem Link muss sich immer zurücknehmen lassen.
            for url in candidates {
                if let entry = OpenDocuments.find(url), entry.undoManager != nil { return (url, entry) }
            }
            if Date() >= deadline || failed() { return nil }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Hinweise

    /// Rückfrage, wenn der Link nicht aus MintMarkPDF kam.
    private static func confirm(_ request: ExternalNodeRequest) -> Bool {
        let alert = NSAlert()
        alert.messageText = L("Knoten aus einem Link anlegen?")
        var details = L("„%@“ wird in der Mindmap „%@“ angelegt. Der Link kam nicht aus MintMarkPDF.",
                        ExternalNodeRequest.shortened(request.title, to: 80),
                        request.file.lastPathComponent)
        // Alles zeigen, was mitkommt – auch Notiz und Link des neuen Knotens.
        if let note = request.note, !note.isEmpty {
            details += "\n\n" + L("Notiz: %@", ExternalNodeRequest.shortened(note, to: 120))
        }
        if let link = request.link, !link.isEmpty {
            details += "\n" + L("Link: %@", ExternalNodeRequest.shortened(link, to: 80))
        }
        alert.informativeText = details
        alert.addButton(withTitle: L("Anlegen"))
        let cancel = alert.addButton(withTitle: L("Abbrechen"))
        // Bewusst ohne Standardknopf: ↩ bestätigt hier nichts (Regel 13). Wer gerade woanders tippt,
        // legt so nicht aus Versehen etwas an – „Anlegen“ braucht einen Klick, Esc bricht ab.
        alert.buttons.first?.keyEquivalent = ""
        cancel.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showAlert(_ message: String, info: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.runModal()
    }
}

/// Hinweise „Knoten … angelegt“ über der Map, je Dokument (1.3).
final class ExternalNodeNotices: ObservableObject {
    static let shared = ExternalNodeNotices()

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let nodeID: UUID
        let message: String
        /// Stand direkt nach dem Anlegen. Solange das Dokument so aussieht, ist der oberste
        /// Rückgängig-Schritt das Anlegen (auch nach Rückgängig einer späteren Änderung).
        let stateAfter: MindMapDocumentData
        let actionName: String
    }

    @Published private(set) var notices: [String: Notice] = [:]

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    func post(_ notice: Notice, for url: URL) {
        notices[Self.key(url)] = notice
    }

    func notice(for url: URL?) -> Notice? {
        url.flatMap { notices[Self.key($0)] }
    }

    func dismiss(_ id: UUID, for url: URL) {
        guard notices[Self.key(url)]?.id == id else { return }
        notices[Self.key(url)] = nil
    }

    /// „Rückgängig“ im Hinweis nur, solange der oberste Schritt noch das Anlegen ist –
    /// sonst nähme der Knopf eine spätere Änderung zurück.
    static func canUndo(_ notice: Notice, current: MindMapDocumentData, undoManager: UndoManager?) -> Bool {
        guard let undoManager, undoManager.canUndo, current == notice.stateAfter else { return false }
        return undoManager.undoActionName == L(notice.actionName)
    }
}

/// Hinweis oben im Editorfenster: „Knoten … aus MintMarkPDF angelegt“ mit „Rückgängig“ (1.3).
/// Verschwindet nach 15 Sekunden oder mit ✕.
struct ExternalNodeBanner: View {
    let fileURL: URL?
    @ObservedObject var document: MindMapFile
    let undoManager: UndoManager?
    @ObservedObject private var notices = ExternalNodeNotices.shared

    var body: some View {
        if let fileURL, let notice = notices.notice(for: fileURL) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                Text(notice.message)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                if ExternalNodeNotices.canUndo(notice, current: document.data, undoManager: undoManager) {
                    Button("Rückgängig") {
                        undoManager?.undo()
                        notices.dismiss(notice.id, for: fileURL)
                    }
                }
                Button {
                    notices.dismiss(notice.id, for: fileURL)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Hinweis schließen")
                .accessibilityLabel(L("Hinweis schließen"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .task(id: notice.id) {
                do {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                } catch {
                    return
                }
                notices.dismiss(notice.id, for: fileURL)
            }
        }
    }
}
