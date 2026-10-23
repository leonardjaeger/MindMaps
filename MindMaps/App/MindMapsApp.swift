import SwiftUI

@main
struct MindMapsApp: App {
    /// Nimmt `mindmaps://`-Links an (M7).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Die Bibliothek öffnet sich beim Start (Fenster › Bibliothek, ⇧ ⌘ L).
        Window("Bibliothek", id: LibraryView.windowID) {
            LibraryView()
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1040, height: 680)
        // Eigener Menüeintrag mit ⇧ ⌘ L steht in AppCommands – den automatischen weglassen.
        .commandsRemoved()

        DocumentGroup(newDocument: { MindMapFile() }) { file in
            EditorView(document: file.document, fileURL: file.fileURL)
                .frame(minWidth: 480, minHeight: 420)
        }
        // Startgröße (1.1.2): passt auf ein 13-Zoll-MacBook (1440 × 900 bzw. 1470 × 956) mit Platz für Dock und Menüleiste.
        .defaultSize(width: 1200, height: 780)
        .commands {
            AppCommands()
        }

        Settings {
            SettingsView()
        }
    }
}
