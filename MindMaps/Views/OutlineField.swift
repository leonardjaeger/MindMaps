import SwiftUI
import AppKit

/// Rückmeldungen der Outline an das Fenster.
struct OutlineHandlers {
    /// Eine Zeile hat den Cursor bekommen.
    var focused: (UUID) -> Void
    /// Bearbeiten einer Zeile beendet – Text übernehmen.
    var endEditing: (UUID, String) -> Void
    /// Text beim Tippen (damit die Map sofort mitläuft).
    var liveText: (UUID, String) -> Void
    /// ↩, Tab, ⇧ Tab, ↑, ↓ in einer Zeile. Liefert `true`, wenn der Befehl erledigt wurde.
    var command: (UUID, OutlineField.Command, String) -> Bool
    var toggleCollapsed: (UUID) -> Void
    /// Gezogenen Knoten (1. ID) vor, in oder nach einem anderen (2. ID) ablegen.
    var move: (UUID, UUID, OutlineDropPosition) -> Void
    var canMove: (UUID, UUID, OutlineDropPosition) -> Bool
    /// ⌫ bei ausgewählter Zeile (ohne Cursor im Text).
    var delete: () -> Void
    /// Kästchen angeklickt (M6).
    var toggleDone: (UUID) -> Void = { _ in }
    /// Notiz-Symbol angeklickt (M6).
    var openNote: (UUID) -> Void = { _ in }
    /// Rechtsklick auf eine Zeile (M7).
    var contextMenu: (UUID) -> [MenuEntry] = { _ in [] }
}

/// Wohin ein gezogener Knoten relativ zu einer Zeile kommt.
enum OutlineDropPosition: Equatable {
    /// obere Zeilenhälfte: davor, gleiche Ebene
    case before
    /// Mitte: als letzter Unterknoten hinein
    case inside
    /// untere Zeilenhälfte: danach, gleiche Ebene
    case after
}

/// Textfeld einer Outline-Zeile.
///
/// Ein AppKit-Textfeld statt `TextField`, weil nur so Tab, ⇧ Tab und die Pfeiltasten
/// zuverlässig abgefangen werden können – `TextField` würde mit Tab zum nächsten Feld springen.
struct OutlineField: NSViewRepresentable {
    enum Command: Equatable {
        case newline, tab, backtab, up, down
    }

    let id: UUID
    let text: String
    let isRoot: Bool
    /// Wird hier die eigene ID gesetzt, bekommt das Feld den Cursor.
    @Binding var focusRequest: UUID?
    let handlers: OutlineHandlers
    /// Schriftgröße (Einstellungen › Bedienung › Textgröße, M12).
    var fontSize: CGFloat = 13
    /// Für VoiceOver: Ebene, Aufgabe, Notiz … (M12).
    var accessibilityDetails: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> FocusReportingTextField {
        let field = FocusReportingTextField(string: text)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = L("Neuer Gedanke")
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: FocusReportingTextField, context: Context) {
        context.coordinator.parent = self
        field.font = isRoot ? .boldSystemFont(ofSize: fontSize + 1) : .systemFont(ofSize: fontSize)
        field.setAccessibilityLabel(accessibilityDetails.isEmpty ? nil : accessibilityDetails)
        let id = self.id
        let handlers = self.handlers
        field.onFocus = { handlers.focused(id) }

        // Änderungen von außen (Map, Rückgängig) übernehmen – aber nicht, während hier getippt wird.
        if field.currentEditor() == nil && field.stringValue != text {
            field.stringValue = text
        }

        if focusRequest == id {
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                if field.currentEditor() == nil {
                    window.makeFirstResponder(field)
                }
                if focusRequest == id { focusRequest = nil }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: OutlineField

        init(parent: OutlineField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.handlers.liveText(parent.id, field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.handlers.endEditing(parent.id, field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let command: Command
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                command = .newline
            case #selector(NSResponder.insertTab(_:)):
                command = .tab
            case #selector(NSResponder.insertBacktab(_:)):
                command = .backtab
            case #selector(NSResponder.moveUp(_:)):
                command = .up
            case #selector(NSResponder.moveDown(_:)):
                command = .down
            case #selector(NSResponder.cancelOperation(_:)):
                // Esc: alten Text zurück und Bearbeiten beenden.
                textView.string = parent.text
                control.window?.makeFirstResponder(nil)
                return true
            default:
                return false
            }
            return parent.handlers.command(parent.id, command, textView.string)
        }
    }
}

/// Textfeld, das meldet, wenn es den Cursor bekommt (auch per Klick, ohne zu tippen).
final class FocusReportingTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}
