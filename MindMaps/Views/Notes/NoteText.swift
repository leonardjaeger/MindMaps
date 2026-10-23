import AppKit

/// Wandelt Notizen zwischen gespeichertem Markdown und formatiertem Text (für das Textfeld) um.
///
/// Listen erscheinen im Textfeld als „•⇥“ bzw. „1.⇥“ am Absatzanfang; beim Zurückwandeln
/// wird daraus wieder „- “ bzw. „1. “.
enum NoteText {
    static let fontSize: CGFloat = 13
    static var baseFont: NSFont { .systemFont(ofSize: fontSize) }
    static let listIndent: CGFloat = 20
    static let bulletPrefix = "•\t"

    // MARK: - Markdown → formatierter Text

    static func attributedString(fromMarkdown markdown: String) -> NSAttributedString {
        attributedString(from: NoteMarkup.parse(markdown))
    }

    static func attributedString(from paragraphs: [NoteParagraph]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, paragraph) in paragraphs.enumerated() {
            let prefix: String
            switch paragraph.kind {
            case .plain: prefix = ""
            case .bullet: prefix = bulletPrefix
            case .numbered(let n): prefix = "\(n).\t"
            }
            let style = paragraphStyle(isList: paragraph.kind != .plain)
            if !prefix.isEmpty {
                result.append(NSAttributedString(string: prefix, attributes: baseAttributes(style)))
            }
            for span in paragraph.spans {
                var attributes = baseAttributes(style)
                attributes[.font] = font(bold: span.bold, italic: span.italic)
                if let link = span.link, let url = URL(string: link) {
                    attributes[.link] = url
                }
                result.append(NSAttributedString(string: span.text, attributes: attributes))
            }
            if index < paragraphs.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes(style)))
            }
        }
        return result
    }

    static func baseAttributes(_ style: NSParagraphStyle = paragraphStyle(isList: false)) -> [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: style]
    }

    static func paragraphStyle(isList: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = 3
        if isList {
            style.headIndent = listIndent
            style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent)]
            style.defaultTabInterval = listIndent
        }
        return style
    }

    static func font(bold: Bool, italic: Bool) -> NSFont {
        var font = baseFont
        let manager = NSFontManager.shared
        if bold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    // MARK: - Formatierter Text → Markdown

    static func markdown(from text: NSAttributedString) -> String {
        NoteMarkup.markdown(paragraphs(from: text))
    }

    static func paragraphs(from text: NSAttributedString) -> [NoteParagraph] {
        let string = text.string as NSString
        guard string.length > 0 else { return [] }
        var result: [NoteParagraph] = []
        var location = 0
        while location <= string.length {
            let lineEnd = string.range(of: "\n", options: [], range: NSRange(location: location, length: string.length - location))
            let end = lineEnd.location == NSNotFound ? string.length : lineEnd.location
            var range = NSRange(location: location, length: end - location)
            var kind = NoteParagraph.Kind.plain
            let line = string.substring(with: range)
            if let prefix = listPrefix(of: line) {
                kind = prefix.kind
                range.location += prefix.length
                range.length -= prefix.length
            }
            var spans: [NoteSpan] = []
            if range.length > 0 {
                text.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
                    var span = NoteSpan(text: string.substring(with: subrange))
                    if let font = attributes[.font] as? NSFont {
                        let traits = NSFontManager.shared.traits(of: font)
                        span.bold = traits.contains(.boldFontMask)
                        span.italic = traits.contains(.italicFontMask)
                    }
                    if let url = attributes[.link] as? URL {
                        span.link = url.absoluteString
                    } else if let link = attributes[.link] as? String {
                        span.link = link
                    }
                    spans.append(span)
                }
            }
            result.append(NoteParagraph(kind: kind, spans: NoteMarkup.merged(spans)))
            if lineEnd.location == NSNotFound { break }
            location = end + 1
        }
        // Leere Absätze am Ende weglassen.
        while let last = result.last, last.kind == .plain, last.spans.isEmpty { result.removeLast() }
        return result
    }

    /// „•⇥“, „• “, „1.⇥“ am Zeilenanfang.
    static func listPrefix(of line: String) -> (kind: NoteParagraph.Kind, length: Int)? {
        if line.hasPrefix("•\t") || line.hasPrefix("• ") { return (.bullet, 2) }
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count), let n = Int(digits) else { return nil }
        let rest = line.dropFirst(digits.count)
        if rest.hasPrefix(".\t") || rest.hasPrefix(". ") {
            return (.numbered(n), digits.count + 2)
        }
        return nil
    }
}
