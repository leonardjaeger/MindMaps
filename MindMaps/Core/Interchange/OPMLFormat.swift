import Foundation

/// OPML 2.0 – das übliche Austauschformat für Gliederungen und Mindmaps.
enum OPMLFormat {

    static func export(_ root: Node, title: String? = nil) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>\(XMLText.escape(title ?? root.text))</title>",
            "  </head>",
            "  <body>",
        ]
        func add(_ node: Node, _ depth: Int) {
            let indent = String(repeating: "  ", count: depth + 2)
            var text = "text=\"\(XMLText.escape(node.text))\""
            if !node.note.isEmpty { text += " _note=\"\(XMLText.escape(node.note))\"" }
            if let task = node.task { text += " _status=\"\(task == .done ? "checked" : "unchecked")\"" }
            if node.children.isEmpty {
                lines.append("\(indent)<outline \(text)/>")
            } else {
                lines.append("\(indent)<outline \(text)>")
                node.children.forEach { add($0, depth + 1) }
                lines.append("\(indent)</outline>")
            }
        }
        add(root, 0)
        lines.append("  </body>")
        lines.append("</opml>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Enthält `<body>` genau ein oberstes `<outline>`, ist es der Hauptknoten;
    /// sonst wird der Titel (bzw. Dateiname) zum Hauptknoten.
    static func parse(_ data: Data, fallbackTitle: String) throws -> Node {
        let delegate = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawOPML else {
            let reason = parser.parserError?.localizedDescription ?? "keine OPML-Datei"
            throw MindMapImporter.ImportError.unreadable(reason)
        }
        let title = delegate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        delegate.top.text = title.isEmpty ? fallbackTitle : title
        return try OutlineBuilder.finish(delegate.top)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let top = OutlineBuilder("")
        var stack: [OutlineBuilder] = []
        var title = ""
        var inTitle = false
        var inBody = false
        var sawOPML = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name.lowercased() {
            case "opml": sawOPML = true
            case "title": inTitle = !inBody
            case "body": inBody = true
            case "outline" where inBody:
                let text = attributes["text"] ?? attributes["title"] ?? ""
                let parent = stack.last ?? top
                let node = parent.add(text)
                node.note = attributes["_note"] ?? ""
                switch attributes["_status"] {
                case "checked"?: node.task = .done
                case "unchecked"?: node.task = .open
                default: break
                }
                stack.append(node)
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            switch name.lowercased() {
            case "title": inTitle = false
            case "body": inBody = false
            case "outline" where inBody: _ = stack.popLast()
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inTitle { title += string }
        }
    }
}
