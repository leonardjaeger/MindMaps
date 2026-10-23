import AppKit
import os

/// Öffnet Links aus Knoten: MindMaps-Links in der App (am richtigen Knoten), alles andere im Standardprogramm.
@MainActor
enum LinkOpener {
    /// `sender`: Bundle-ID der App, die den Link geschickt hat (nur bei Links von außen, sonst `nil`).
    static func open(_ link: String, sender: String? = nil) {
        // Zuerst Anlegen-Links (1.3): `DocumentLink.parse` hielte `mindmaps://add?file=…` sonst für einen Öffnen-Link.
        if ExternalNodeRequest.isAddLink(link) {
            ExternalNodeAdder.handle(link, sender: sender)
            return
        }
        if let target = DocumentLink.parse(link) {
            guard FileManager.default.fileExists(atPath: target.file.path) else {
                let alert = NSAlert()
                alert.messageText = L("Das verlinkte Dokument wurde nicht gefunden.")
                alert.informativeText = target.file.path
                alert.runModal()
                return
            }
            if let node = target.node { PendingSelection.set(node, for: target.file) }
            NSDocumentController.shared.openDocument(withContentsOf: target.file, display: true) { _, _, _ in }
            return
        }
        // Andere `mindmaps://`-Links nicht an macOS weitergeben – sie kämen hierher zurück (Endlosschleife).
        if URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines))?.scheme?.lowercased()
            == DocumentLink.scheme {
            NSSound.beep()
            return
        }
        // `mintmarkpdf://`-Links (PDF-Stellen, 1.3) öffnet macOS in MintMarkPDF.
        if let url = URL(string: DocumentLink.normalized(link)) {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Nimmt `mindmaps://`-Links von außen an (z. B. aus Safari, Notizen oder Erinnerungen) und Spotlight-Treffer.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Link-Empfänger vor dem Start registrieren (1.3): Sonst geht der Link verloren, der MindMaps erst startet
    /// (z. B. „Als Knoten in Mindmap …“ aus MintMarkPDF bei geschlossenem MindMaps).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleURL(_:withReply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘ O wechselt die Ansicht (1.1.2) – „Ablage › Öffnen …“ bekommt dafür ⇧ ⌘ O.
        // Das Menü baut macOS/SwiftUI selbst; beim Start und bei jedem Fensterwechsel nachziehen.
        DispatchQueue.main.async { Self.moveOpenShortcut() }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Self.moveOpenShortcut() }
            }
        }
    }

    /// Im Menü „Ablage“: jeder Eintrag mit ⌘ O (das ist „Öffnen …“) bekommt ⇧ ⌘ O.
    @MainActor
    static func moveOpenShortcut() {
        guard let menus = NSApp.mainMenu?.items, menus.count > 1, let file = menus[1].submenu else { return }
        for item in file.items where item.keyEquivalent == "o"
            && item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control]) == .command {
            item.keyEquivalent = "O"
            item.keyEquivalentModifierMask = .command
        }
    }

    /// Treffer aus Spotlight öffnen (M9).
    func application(_ application: NSApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        MainActor.assumeIsolated { SpotlightIndexer.open(userActivity) }
    }

    /// Protokoll der Link-Annahme – nur Weg und Ergebnis, nie Inhalte (Regel 14).
    static let log = Logger(subsystem: "de.leonardjaeger.MindMaps", category: "links")

    @objc private func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        let sender = Self.senderBundleID(of: event)
        Self.log.info("Link empfangen (\(link.count, privacy: .public) Zeichen, Absender MintMarkPDF: \(sender == ExternalNodeAdder.mintMarkBundleID, privacy: .public), Absender bekannt: \(sender != nil, privacy: .public))")
        MainActor.assumeIsolated { LinkOpener.open(link, sender: sender) }
    }

    /// Bundle-ID der App, die den Link geschickt hat (1.3) – `nil`, wenn macOS keinen Absender nennt.
    /// Entscheidet, ob ein Anlegen-Link ohne Rückfrage ausgeführt wird (nur aus MintMarkPDF).
    static func senderBundleID(of event: NSAppleEventDescriptor) -> String? {
        guard let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
