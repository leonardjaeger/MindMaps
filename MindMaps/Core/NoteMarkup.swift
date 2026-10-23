import Foundation

/// Ein Stück Notiztext mit einheitlicher Formatierung.
struct NoteSpan: Equatable {
    var text: String
    var bold = false
    var italic = false
    var link: String?

    func sameStyle(as other: NoteSpan) -> Bool {
        bold == other.bold && italic == other.italic && link == other.link
    }
}

/// Ein Absatz der Notiz: normaler Text, Aufzählung oder nummerierte Liste.
struct NoteParagraph: Equatable {
    enum Kind: Equatable {
        case plain
        case bullet
        case numbered(Int)
    }

    var kind: Kind = .plain
    var spans: [NoteSpan] = []

    var plainText: String { spans.map(\.text).joined() }
}

/// Notizen werden als kleine Markdown-Teilmenge gespeichert – lesbar in der `document.json`,
/// verlustfrei hin und zurück und direkt für den Markdown-Export geeignet.
///
/// Unterstützt: `**fett**`, `*kursiv*` (auch `_kursiv_`), `[Text](https://…)`,
/// Aufzählung `- ` (auch `* `, `+ `), nummerierte Liste `1. `, Backslash maskiert Sonderzeichen.
enum NoteMarkup {

    // MARK: - Markdown → Absätze

    static func parse(_ markdown: String) -> [NoteParagraph] {
        guard !markdown.isEmpty else { return [] }
        return MarkdownFormat.lines(of: markdown).map(parseLine)
    }

    private static func parseLine(_ line: String) -> NoteParagraph {
        var rest = Substring(line)
        var kind = NoteParagraph.Kind.plain
        let trimmed = rest.drop { $0 == " " || $0 == "\t" }
        if let first = trimmed.first, "-*+".contains(first), trimmed.dropFirst().first == " " {
            kind = .bullet
            rest = trimmed.dropFirst(2)
        } else {
            let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
            let after = trimmed.dropFirst(digits.count)
            if (1...9).contains(digits.count), after.hasPrefix(". "), let n = Int(digits) {
                kind = .numbered(n)
                rest = after.dropFirst(2)
            }
        }
        return NoteParagraph(kind: kind, spans: parseInline(String(rest)))
    }

    /// Fett, kursiv und Links innerhalb einer Zeile. Nicht geschlossene Zeichen bleiben stehen.
    static func parseInline(_ text: String) -> [NoteSpan] {
        let chars = Array(text)
        var spans: [NoteSpan] = []
        var current = NoteSpan(text: "")
        var bold = false
        var italic: Character?   // "*" oder "_", mit dem die Kursivschrift begann

        func flush() {
            if !current.text.isEmpty { spans.append(current) }
            current = NoteSpan(text: "", bold: bold, italic: italic != nil)
        }

        func hasClosing(_ marker: [Character], from start: Int) -> Bool {
            var i = start
            while i + marker.count <= chars.count {
                if chars[i] == "\\" { i += 2; continue }
                if Array(chars[i..<(i + marker.count)]) == marker {
                    // „**“ nicht als Ende von „*“ werten.
                    if marker == ["*"], i + 1 < chars.count, chars[i + 1] == "*" { i += 2; continue }
                    return true
                }
                i += 1
            }
            return false
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                current.text.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*", italic != "*" || bold {
                if bold || hasClosing(["*", "*"], from: i + 2) {
                    flush()
                    bold.toggle()
                    current.bold = bold
                    i += 2
                    continue
                }
            }
            if c == "*" || c == "_" {
                if italic == c {
                    flush()
                    italic = nil
                    current.italic = false
                    i += 1
                    continue
                }
                if italic == nil, hasClosing([c], from: i + 1), i + 1 < chars.count, chars[i + 1] != " " {
                    flush()
                    italic = c
                    current.italic = true
                    i += 1
                    continue
                }
            }
            if c == "[", let link = parseLink(chars, at: i) {
                flush()
                for inner in parseInline(link.label) {
                    var span = inner
                    span.bold = span.bold || bold
                    span.italic = span.italic || italic != nil
                    span.link = link.url
                    spans.append(span)
                }
                i = link.end
                continue
            }
            current.text.append(c)
            i += 1
        }
        flush()
        return merged(spans)
    }

    /// `[Text](url)` ab Position `start`; liefert Text, URL und Position nach der Klammer.
    private static func parseLink(_ chars: [Character], at start: Int) -> (label: String, url: String, end: Int)? {
        var depth = 0
        var i = start
        var closeBracket: Int?
        while i < chars.count {
            if chars[i] == "\\" { i += 2; continue }
            if chars[i] == "[" { depth += 1 }
            if chars[i] == "]" {
                depth -= 1
                if depth == 0 { closeBracket = i; break }
            }
            i += 1
        }
        guard let close = closeBracket, close + 1 < chars.count, chars[close + 1] == "(" else { return nil }
        guard let closeParen = chars[(close + 2)...].firstIndex(of: ")") else { return nil }
        let url = String(chars[(close + 2)..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !url.contains(" ") else { return nil }
        return (String(chars[(start + 1)..<close]), url, closeParen + 1)
    }

    /// Fasst benachbarte Stücke mit gleicher Formatierung zusammen.
    static func merged(_ spans: [NoteSpan]) -> [NoteSpan] {
        var result: [NoteSpan] = []
        for span in spans where !span.text.isEmpty {
            if let last = result.last, last.sameStyle(as: span) {
                result[result.count - 1].text += span.text
            } else {
                result.append(span)
            }
        }
        return result
    }

    // MARK: - Absätze → Markdown

    static func markdown(_ paragraphs: [NoteParagraph]) -> String {
        paragraphs.map(markdownLine).joined(separator: "\n")
    }

    private static func markdownLine(_ paragraph: NoteParagraph) -> String {
        var body = merged(paragraph.spans).map(markdownSpan).joined()
        switch paragraph.kind {
        case .bullet:
            return "- " + body
        case .numbered(let n):
            return "\(n). " + body
        case .plain:
            // Normaler Text, der wie eine Liste aussieht, wird maskiert.
            if let first = body.first, "-+".contains(first), body.dropFirst().first == " " {
                body = "\\" + body
            } else {
                let digits = body.prefix { $0.isASCII && $0.isNumber }
                if !digits.isEmpty, body.dropFirst(digits.count).hasPrefix(". ") {
                    body.insert("\\", at: body.index(body.startIndex, offsetBy: digits.count))
                }
            }
            return body
        }
    }

    private static func markdownSpan(_ span: NoteSpan) -> String {
        // Leerzeichen am Rand gehören nicht in die Markierung („** fett**“ wäre kein Fett).
        let text = span.text
        let core = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard !core.isEmpty else { return escape(text) }
        let leading = String(text.prefix { $0 == " " || $0 == "\t" })
        let trailing = String(text.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
        var out = escape(core)
        if span.italic { out = "*" + out + "*" }
        if span.bold { out = "**" + out + "**" }
        if let link = span.link { out = "[" + out + "](" + link + ")" }
        return escape(leading) + out + escape(trailing)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            if "\\*_[]".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    // MARK: - Klartext

    /// Notiz ohne Markierungen (für Vorschau, Suche, Export als Klartext).
    static func plainText(_ markdown: String) -> String {
        parse(markdown).map { paragraph in
            switch paragraph.kind {
            case .plain: return paragraph.plainText
            case .bullet: return "• " + paragraph.plainText
            case .numbered(let n): return "\(n). " + paragraph.plainText
            }
        }.joined(separator: "\n")
    }
}
