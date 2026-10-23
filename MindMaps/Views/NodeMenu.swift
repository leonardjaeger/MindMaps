import SwiftUI
import AppKit

/// Einträge eines Kontextmenüs – einmal beschrieben, in der Map als AppKit-Menü,
/// in der Outline als SwiftUI-Menü angezeigt (M7).
indirect enum MenuEntry {
    case action(String, systemImage: String? = nil, enabled: Bool = true, run: () -> Void)
    case toggle(String, isOn: Bool, run: () -> Void)
    case submenu(String, systemImage: String? = nil, [MenuEntry])
    case divider
}

// MARK: - AppKit (Rechtsklick in der Map)

extension NSMenu {
    static func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .action(let title, let symbol, let enabled, let run):
                let item = ClosureMenuItem(title: title, run: run)
                item.isEnabled = enabled
                if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                menu.addItem(item)
            case .toggle(let title, let isOn, let run):
                let item = ClosureMenuItem(title: title, run: run)
                item.state = isOn ? .on : .off
                menu.addItem(item)
            case .submenu(let title, let symbol, let children):
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                item.submenu = build(children)
                menu.addItem(item)
            case .divider:
                menu.addItem(.separator())
            }
        }
        return menu
    }
}

/// Menüeintrag, der eine Swift-Funktion ausführt.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(runClosure), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("nicht verwendet")
    }

    @objc private func runClosure() { run() }
}

// MARK: - SwiftUI (Rechtsklick in der Outline)

struct MenuEntriesView: View {
    let entries: [MenuEntry]

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            Self.view(for: entry)
        }
    }

    static func view(for entry: MenuEntry) -> AnyView {
        switch entry {
        case .action(let title, let symbol, let enabled, let run):
            if let symbol {
                return AnyView(Button(action: run) { Label(title, systemImage: symbol) }.disabled(!enabled))
            }
            return AnyView(Button(title, action: run).disabled(!enabled))
        case .toggle(let title, let isOn, let run):
            return AnyView(Toggle(title, isOn: Binding(get: { isOn }, set: { _ in run() })))
        case .submenu(let title, _, let children):
            return AnyView(Menu(title) { MenuEntriesView(entries: children) })
        case .divider:
            return AnyView(Divider())
        }
    }
}

// MARK: - Kurze Eingabe (Link, Formel, Beschriftung)

enum TextPrompt {
    /// Fragt einen Text ab; `nil` = abgebrochen.
    @MainActor
    static func run(title: String, message: String, initial: String, placeholder: String = "",
                    width: CGFloat = 340) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        field.stringValue = initial
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Abbrechen"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}
