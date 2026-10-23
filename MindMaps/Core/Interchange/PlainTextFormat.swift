import Foundation

/// Klartext: ein Knoten pro Zeile, Ebenen durch Einrückung (Tabulator oder Leerzeichen).
enum PlainTextFormat {

    static func export(_ root: Node) -> String {
        var lines: [String] = []
        func add(_ node: Node, _ depth: Int) {
            let text = node.text.components(separatedBy: .newlines).joined(separator: " ")
            lines.append(String(repeating: "\t", count: depth) + text)
            node.children.forEach { add($0, depth + 1) }
        }
        add(root, 0)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Einrückung mit Tabulatoren oder Leerzeichen (die kleinste vorkommende Einrückung ist eine Ebene).
    /// Aufzählungszeichen am Zeilenanfang („- “, „• “, „* “) fallen weg.
    static func parse(_ text: String, fallbackTitle: String) throws -> Node {
        struct Line { var tabs: Int; var spaces: Int; var text: String }
        var parsed: [Line] = []
        for raw in MarkdownFormat.lines(of: text) {
            var tabs = 0, spaces = 0
            var index = raw.startIndex
            while index < raw.endIndex, raw[index] == "\t" || raw[index] == " " {
                if raw[index] == "\t" { tabs += 1 } else { spaces += 1 }
                index = raw.index(after: index)
            }
            var content = raw[index...].trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            for bullet in ["- ", "• ", "* ", "– "] where content.hasPrefix(bullet) {
                content = String(content.dropFirst(bullet.count))
            }
            parsed.append(Line(tabs: tabs, spaces: spaces, text: content))
        }
        let unit = parsed.map(\.spaces).filter { $0 > 0 }.min() ?? 1

        let top = OutlineBuilder(fallbackTitle)
        var stack: [(level: Int, node: OutlineBuilder)] = [(-1, top)]
        for line in parsed {
            let level = line.tabs + line.spaces / unit
            while stack.count > 1 && stack.last!.level >= level { stack.removeLast() }
            let node = stack.last!.node.add(line.text)
            stack.append((level, node))
        }
        return try OutlineBuilder.finish(top)
    }
}
