import SwiftUI
import AppKit

/// Notiz-Editor: Formatierungsleiste (fett, kursiv, Listen, Link) und Textfeld.
/// Der Text wird nach kurzer Tipppause und beim Verlassen übernommen (je ein Rückgängig-Schritt).
struct NoteEditorView: View {
    let markdown: String
    let onCommit: (String) -> Void
    var focusOnAppear = false
    /// Jede Änderung setzt den Cursor in die Notiz.
    var focusToken = 0

    @State private var controller = NoteEditorController()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                formatButton("bold", help: L("Fett (⌘ B)")) { controller.toggleTrait(.boldFontMask) }
                formatButton("italic", help: L("Kursiv (⌘ K)")) { controller.toggleTrait(.italicFontMask) }
                Divider().frame(height: 16).padding(.horizontal, 4)
                formatButton("list.bullet", help: L("Aufzählung")) { controller.toggleList(numbered: false) }
                formatButton("list.number", help: L("Nummerierte Liste")) { controller.toggleList(numbered: true) }
                Divider().frame(height: 16).padding(.horizontal, 4)
                formatButton("link", help: L("Link (⌥ ⌘ K)")) { controller.editLink() }
                Spacer()
            }
            NoteTextViewRepresentable(markdown: markdown, onCommit: onCommit,
                                      controller: controller, focusOnAppear: focusOnAppear,
                                      focusToken: focusToken)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
        }
    }

    private func formatButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Notiz eines Knotens im Popover (Klick auf das Blatt-Symbol in der Map).
struct NotePopover: View {
    let node: Node?
    let actions: DocumentActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let node {
                Text(node.text.isEmpty ? L("Notiz") : node.text)
                    .font(.headline)
                    .lineLimit(2)
                NoteEditorView(markdown: node.note,
                               onCommit: { actions.setNote($0, of: node.id) },
                               focusOnAppear: true)
                    .id(node.id)
            }
        }
        .padding(12)
        .frame(width: 360, height: 280)
    }
}

/// Verbindung zwischen Formatierungsknöpfen und Textfeld.
final class NoteEditorController {
    weak var textView: NoteTextView?

    func toggleTrait(_ trait: NSFontTraitMask) {
        textView?.toggleTrait(trait)
    }

    func toggleList(numbered: Bool) {
        textView?.toggleList(numbered: numbered)
    }

    func editLink() {
        textView?.editLink()
    }
}

struct NoteTextViewRepresentable: NSViewRepresentable {
    let markdown: String
    let onCommit: (String) -> Void
    let controller: NoteEditorController
    let focusOnAppear: Bool
    let focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(onCommit: onCommit) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let textView = NoteTextView(frame: .zero)
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.importsGraphics = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.typingAttributes = NoteText.baseAttributes()
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(NoteText.attributedString(fromMarkdown: markdown))
        scroll.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.lastMarkdown = markdown
        context.coordinator.focusToken = focusToken
        controller.textView = textView

        if focusOnAppear { Self.focus(textView) }
        return scroll
    }

    private static func focus(_ textView: NSTextView) {
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        }
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCommit = onCommit
        if let textView = coordinator.textView {
            controller.textView = textView
            if focusToken != coordinator.focusToken {
                coordinator.focusToken = focusToken
                Self.focus(textView)
            }
            // Änderungen von außen (Rückgängig, Suchen & Ersetzen) übernehmen – nicht während des Tippens.
            if markdown != coordinator.lastMarkdown && !coordinator.hasPendingChanges {
                textView.textStorage?.setAttributedString(NoteText.attributedString(fromMarkdown: markdown))
                coordinator.lastMarkdown = markdown
            }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.commit()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onCommit: (String) -> Void
        weak var textView: NoteTextView?
        var lastMarkdown = ""
        var hasPendingChanges = false
        var focusToken = 0
        private var pending: DispatchWorkItem?

        init(onCommit: @escaping (String) -> Void) {
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            hasPendingChanges = true
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.commit() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }

        func textDidEndEditing(_ notification: Notification) {
            commit()
        }

        func commit() {
            pending?.cancel()
            pending = nil
            guard hasPendingChanges, let storage = textView?.textStorage else { return }
            hasPendingChanges = false
            let markdown = NoteText.markdown(from: storage)
            guard markdown != lastMarkdown else { return }
            lastMarkdown = markdown
            onCommit(markdown)
        }

        /// ↩ in einer Liste setzt die Liste fort; ↩ in einem leeren Listenpunkt beendet sie.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)),
                  let noteView = textView as? NoteTextView else { return false }
            return noteView.continueList()
        }
    }
}

/// ⌘ B (fett), ⌘ K (kursiv) und ⌥ ⌘ K (Link) für Notizen – über die Menüs, damit die Tasten sicher ankommen.
/// Die Aktion geht an das Notizfeld, in dem gerade geschrieben wird. Liefert `false`, wenn keins
/// den Cursor hat – dann gilt die Taste für den ausgewählten Knoten.
@MainActor
enum NoteFormatting {
    @discardableResult static func bold() -> Bool { send(#selector(NoteTextView.formatBold(_:))) }
    @discardableResult static func italic() -> Bool { send(#selector(NoteTextView.formatItalic(_:))) }
    @discardableResult static func link() -> Bool { send(#selector(NoteTextView.formatLink(_:))) }

    private static func send(_ action: Selector) -> Bool {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}

/// Textfeld mit ⌘ B, ⌘ K, ⌥ ⌘ K und Listen.
final class NoteTextView: NSTextView {

    // Aus dem Menü „Format“ (Responder-Kette).
    @objc func formatBold(_ sender: Any?) { toggleTrait(.boldFontMask) }
    @objc func formatItalic(_ sender: Any?) { toggleTrait(.italicFontMask) }
    @objc func formatLink(_ sender: Any?) { editLink() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Nur die echten Sondertasten zählen (Feststelltaste u. Ä. nicht).
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard window?.firstResponder === self, flags == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggleTrait(.boldFontMask); return true
        case "k": toggleTrait(.italicFontMask); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - Fett / kursiv

    func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()
        guard let storage = textStorage else { return }
        if range.length == 0 {
            let font = (typingAttributes[.font] as? NSFont) ?? NoteText.baseFont
            let has = manager.traits(of: font).contains(trait)
            typingAttributes[.font] = has ? manager.convert(font, toNotHaveTrait: trait)
                                          : manager.convert(font, toHaveTrait: trait)
            return
        }
        var allHave = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            let font = (value as? NSFont) ?? NoteText.baseFont
            if !manager.traits(of: font).contains(trait) { allHave = false }
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = (value as? NSFont) ?? NoteText.baseFont
            let new = allHave ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: new, range: subrange)
        }
        storage.endEditing()
        didChangeText()
    }

    // MARK: - Listen

    /// Absätze der Auswahl zur Liste machen – oder die Liste wieder entfernen.
    func toggleList(numbered: Bool) {
        guard let storage = textStorage else { return }
        let string = storage.string as NSString
        let paragraphs = string.paragraphRange(for: selectedRange())
        var ranges: [NSRange] = []
        string.enumerateSubstrings(in: paragraphs, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            ranges.append(range)
        }
        if ranges.isEmpty { ranges = [NSRange(location: paragraphs.location, length: 0)] }

        let allSame = ranges.allSatisfy { range in
            guard let prefix = NoteText.listPrefix(of: string.substring(with: range)) else { return false }
            if case .numbered = prefix.kind { return numbered }
            return !numbered
        }
        guard shouldChangeText(in: paragraphs, replacementString: nil) else { return }
        storage.beginEditing()
        // Von hinten nach vorn, damit die Bereiche gültig bleiben.
        for (index, range) in ranges.enumerated().reversed() {
            let line = string.substring(with: range)
            let old = NoteText.listPrefix(of: line)?.length ?? 0
            let prefix = allSame ? "" : (numbered ? "\(index + 1).\t" : NoteText.bulletPrefix)
            let style = NoteText.paragraphStyle(isList: !prefix.isEmpty)
            storage.replaceCharacters(in: NSRange(location: range.location, length: old),
                                      with: NSAttributedString(string: prefix, attributes: NoteText.baseAttributes(style)))
            let newLength = range.length - old + (prefix as NSString).length
            storage.addAttribute(.paragraphStyle, value: style,
                                 range: NSRange(location: range.location, length: max(newLength, 0)))
        }
        storage.endEditing()
        didChangeText()
    }

    /// ↩ in einem Listenpunkt: nächster Punkt; in einem leeren Punkt: Liste beenden.
    func continueList() -> Bool {
        guard let storage = textStorage else { return false }
        let string = storage.string as NSString
        let cursor = selectedRange()
        let paragraph = string.paragraphRange(for: NSRange(location: cursor.location, length: 0))
        var line = string.substring(with: paragraph)
        if line.hasSuffix("\n") { line.removeLast() }
        guard let prefix = NoteText.listPrefix(of: line) else { return false }

        if (line as NSString).length == prefix.length {
            // Leerer Punkt: Aufzählungszeichen entfernen, Liste endet.
            let range = NSRange(location: paragraph.location, length: prefix.length)
            guard shouldChangeText(in: range, replacementString: "") else { return true }
            storage.replaceCharacters(in: range, with: "")
            storage.addAttribute(.paragraphStyle, value: NoteText.paragraphStyle(isList: false),
                                 range: NSRange(location: paragraph.location, length: 0))
            typingAttributes[.paragraphStyle] = NoteText.paragraphStyle(isList: false)
            didChangeText()
            return true
        }
        let next: String
        switch prefix.kind {
        case .numbered(let n): next = "\(n + 1).\t"
        default: next = NoteText.bulletPrefix
        }
        var attributes = NoteText.baseAttributes(NoteText.paragraphStyle(isList: true))
        if let font = typingAttributes[.font] { attributes[.font] = font }
        let insertion = NSAttributedString(string: "\n" + next, attributes: attributes)
        guard shouldChangeText(in: cursor, replacementString: insertion.string) else { return true }
        storage.replaceCharacters(in: cursor, with: insertion)
        setSelectedRange(NSRange(location: cursor.location + insertion.length, length: 0))
        didChangeText()
        return true
    }

    // MARK: - Link

    func editLink() {
        guard let storage = textStorage else { return }
        let range = selectedRange()
        var current = ""
        if range.length > 0, let value = storage.attribute(.link, at: range.location, effectiveRange: nil) {
            current = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
        } else if range.length > 0 {
            let selected = (storage.string as NSString).substring(with: range)
            if selected.hasPrefix("http") { current = selected }
        }

        let alert = NSAlert()
        alert.messageText = range.length > 0 ? L("Link für die Auswahl") : L("Link einfügen")
        alert.informativeText = "Webadresse, z. B. https://www.ph-freiburg.de. Leer lassen entfernt den Link."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = current
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: L("OK"))
        alert.addButton(withTitle: L("Abbrechen"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        var address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty, !address.contains("://"), !address.hasPrefix("mailto:") {
            address = "https://" + address
        }
        let url = URL(string: address)
        if range.length == 0 {
            guard let url else { return }
            var attributes = typingAttributes
            attributes[.link] = url
            let text = NSAttributedString(string: address, attributes: attributes)
            guard shouldChangeText(in: range, replacementString: address) else { return }
            storage.replaceCharacters(in: range, with: text)
            didChangeText()
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        if let url, !address.isEmpty {
            storage.addAttribute(.link, value: url, range: range)
        } else {
            storage.removeAttribute(.link, range: range)
        }
        didChangeText()
    }
}
