import Foundation

/// Markdown hin und zurück.
///
/// Export: Hauptknoten `# …`, Hauptäste `## …`, alles darunter als eingerückte Liste (4 Leerzeichen je Ebene).
/// Aufgaben als `- [ ]` / `- [x]`, Notizen als Zitat (`> …`) direkt unter ihrem Knoten (seit M6).
/// Import: Überschriften (`#` bis `######`, auch mit `===`/`---` unterstrichen) bilden die Ebenen,
/// Listen (`-`, `*`, `+`, `1.`) hängen unter der letzten Überschrift, Absätze werden eigene Knoten,
/// Zitatzeilen werden zur Notiz des Knotens darüber.
enum MarkdownFormat {

    // MARK: - Export

    static func export(_ root: Node) -> String {
        var lines = ["# " + singleLine(root.text)]
        appendNote(root.note, indent: "", to: &lines)
        for child in root.children {
            lines.append("")
            lines.append("## " + singleLine(child.text))
            appendNote(child.note, indent: "", to: &lines)
            if !child.children.isEmpty {
                lines.append("")
                appendList(child.children, level: 0, to: &lines)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendList(_ nodes: [Node], level: Int, to lines: inout [String]) {
        let indent = String(repeating: "    ", count: level)
        for node in nodes {
            let parts = node.text.components(separatedBy: "\n")
            let box: String
            switch node.task {
            case .open?: box = "[ ] "
            case .done?: box = "[x] "
            case nil: box = ""
            }
            lines.append(indent + "- " + box + parts[0])
            // Weitere Zeilen eines Knotens: eingerückt unter dem Listenpunkt.
            for part in parts.dropFirst() { lines.append(indent + "  " + part) }
            appendNote(node.note, indent: indent + "  ", to: &lines)
            appendList(node.children, level: level + 1, to: &lines)
        }
    }

    /// Notiz als Zitatblock (jede Zeile mit „> “).
    private static func appendNote(_ note: String, indent: String, to lines: inout [String]) {
        guard !note.isEmpty else { return }
        for line in Self.lines(of: note) { lines.append(indent + (line.isEmpty ? ">" : "> " + line)) }
    }

    /// Überschriften können keinen Zeilenumbruch enthalten.
    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    // MARK: - Import

    static func parse(_ text: String, fallbackTitle: String) throws -> Node {
        let top = OutlineBuilder(fallbackTitle)
        var headings: [(level: Int, node: OutlineBuilder)] = [(0, top)]
        var list: [(indent: Int, node: OutlineBuilder)] = []
        var paragraph: [String] = []
        var fence: (marker: String, lines: [String])?
        /// Zuletzt angelegter Knoten – bekommt folgende Zitatzeilen als Notiz.
        var lastNode: OutlineBuilder?

        func container() -> OutlineBuilder { list.last?.node ?? headings.last!.node }

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            lastNode = headings.last!.node.add(paragraph.joined(separator: " "))
            paragraph = []
        }

        func addHeading(_ title: String, level: Int) {
            flushParagraph()
            list = []
            while headings.count > 1 && headings.last!.level >= level { headings.removeLast() }
            let node = headings.last!.node.add(title)
            headings.append((level, node))
            lastNode = node
        }

        for raw in lines(of: text) {
            let (columns, content) = splitIndent(raw)

            // Codeblöcke (``` oder ~~~) werden ein Knoten mit ihrem Inhalt.
            if var open = fence {
                if content.hasPrefix(open.marker) {
                    lastNode = container().add(open.lines.joined(separator: "\n"))
                    fence = nil
                } else {
                    open.lines.append(raw)
                    fence = open
                }
                continue
            }
            if content.hasPrefix("```") || content.hasPrefix("~~~") {
                flushParagraph()
                fence = (String(content.prefix(3)), [])
                continue
            }

            if content.isEmpty {
                flushParagraph()
                continue
            }

            // Zitat = Notiz des Knotens darüber.
            if content.hasPrefix(">") {
                flushParagraph()
                var line = content.dropFirst()
                if line.hasPrefix(" ") { line = line.dropFirst() }
                if let target = lastNode ?? headings.last?.node {
                    target.note = target.note.isEmpty ? String(line) : target.note + "\n" + line
                }
                continue
            }

            if columns <= 3, let found = heading(content) {
                addHeading(found.title, level: found.level)
                continue
            }

            // Unterstrichene Überschrift: Zeile darüber ist der Titel.
            if columns <= 3, list.isEmpty, paragraph.count == 1, let level = setextLevel(content) {
                let title = paragraph[0]
                paragraph = []
                addHeading(title, level: level)
                continue
            }

            if columns <= 3, isThematicBreak(content) {
                flushParagraph()
                list = []
                continue
            }

            if let item = listItem(content) {
                flushParagraph()
                while let last = list.last, last.indent >= columns { list.removeLast() }
                let node = container().add(item.text)
                node.task = item.task
                list.append((columns, node))
                lastNode = node
                continue
            }

            // Eingerückte Zeile unter einem Listenpunkt gehört zu dessen Text.
            if let last = list.last, columns > last.indent, paragraph.isEmpty {
                last.node.text += "\n" + content
                continue
            }

            list = []
            paragraph.append(content)
        }
        if let open = fence, !open.lines.isEmpty { container().add(open.lines.joined(separator: "\n")) }
        flushParagraph()
        return try OutlineBuilder.finish(top)
    }

    /// Zeilen ohne Zeilenende-Zeichen (\n, \r\n oder \r).
    static func lines(of text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    /// Einrückung in Spalten (Tabulator = bis zur nächsten Viererspalte) und der Rest ohne Leerraum am Ende.
    static func splitIndent(_ line: String) -> (columns: Int, content: String) {
        var columns = 0
        var index = line.startIndex
        while index < line.endIndex {
            let c = line[index]
            if c == " " { columns += 1 } else if c == "\t" { columns += 4 - columns % 4 } else { break }
            index = line.index(after: index)
        }
        let rest = line[index...]
        let trimmed = rest.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return (columns, trimmed)
    }

    private static func heading(_ content: String) -> (level: Int, title: String)? {
        let hashes = content.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = content.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var title = rest.trimmingCharacters(in: .whitespaces)
        // Schließende Rauten („## Titel ##“) weglassen.
        if title.allSatisfy({ $0 == "#" }) {
            title = ""
        } else if let range = title.range(of: "[ \\t]+#+$", options: .regularExpression) {
            title.removeSubrange(range)
        }
        return (hashes, title)
    }

    private static func setextLevel(_ content: String) -> Int? {
        if content.allSatisfy({ $0 == "=" }) { return 1 }
        if content.count >= 2, content.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    private static func isThematicBreak(_ content: String) -> Bool {
        let chars = content.filter { $0 != " " && $0 != "\t" }
        guard chars.count >= 3, let first = chars.first, "-*_".contains(first) else { return false }
        return chars.allSatisfy { $0 == first }
    }

    /// Text eines Listenpunkts (`- `, `* `, `+ `, `1. `, `1) `), sonst nil.
    /// Ein Kästchen `[ ]` / `[x]` am Anfang macht den Knoten zur Aufgabe.
    private static func listItem(_ content: String) -> (text: String, task: TaskMark?)? {
        var rest: Substring
        if let first = content.first, "-*+".contains(first) {
            rest = content.dropFirst()
        } else {
            let digits = content.prefix { $0.isASCII && $0.isNumber }
            guard (1...9).contains(digits.count) else { return nil }
            rest = content.dropFirst(digits.count)
            guard let marker = rest.first, marker == "." || marker == ")" else { return nil }
            rest = rest.dropFirst()
        }
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        var task: TaskMark?
        for (box, mark) in [("[ ] ", TaskMark.open), ("[x] ", .done), ("[X] ", .done)] where text.hasPrefix(box) {
            text = String(text.dropFirst(box.count))
            task = mark
        }
        if text == "[ ]" { text = ""; task = .open }
        if text == "[x]" || text == "[X]" { text = ""; task = .done }
        return (text, task)
    }
}
