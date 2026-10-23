import Foundation

/// FreeMind-Format (`.mm`) – lesen auch Freeplane, XMind, SimpleMind, MindManager u. v. m.
enum FreeMindFormat {

    static func export(_ root: Node) -> String {
        var lines = [#"<map version="1.0.1">"#]
        func add(_ node: Node, depth: Int, position: String?) {
            let indent = String(repeating: " ", count: depth)
            var attributes = "TEXT=\"\(XMLText.escape(node.text))\""
            if let position { attributes += " POSITION=\"\(position)\"" }
            if node.isCollapsed && !node.children.isEmpty { attributes += " FOLDED=\"true\"" }
            if node.children.isEmpty {
                lines.append("\(indent)<node \(attributes)/>")
                return
            }
            lines.append("\(indent)<node \(attributes)>")
            // Wie in der Map: erste Hälfte der Hauptäste rechts, der Rest links.
            let rightCount = (node.children.count + 1) / 2
            for (index, child) in node.children.enumerated() {
                let side = depth == 0 ? (index < rightCount ? "right" : "left") : nil
                add(child, depth: depth + 1, position: side)
            }
            lines.append("\(indent)</node>")
        }
        add(root, depth: 0, position: nil)
        lines.append("</map>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ data: Data, fallbackTitle: String) throws -> Node {
        let delegate = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawMap else {
            let reason = parser.parserError?.localizedDescription ?? "keine FreeMind-Datei"
            throw MindMapImporter.ImportError.unreadable(reason)
        }
        delegate.top.text = fallbackTitle
        return try OutlineBuilder.finish(delegate.top)
    }

    private final class Reader: NSObject, XMLParserDelegate {
        let top = OutlineBuilder("")
        var stack: [OutlineBuilder] = []
        var sawMap = false
        /// Text in `<richcontent TYPE="NODE">` (HTML), wenn ein Knoten kein TEXT-Attribut hat.
        var richDepth = 0
        var richText = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if richDepth > 0 {
                richDepth += 1
                if ["p", "br", "li", "div"].contains(name.lowercased()), !richText.isEmpty { richText += "\n" }
                return
            }
            switch name {
            case "map":
                sawMap = true
            case "node":
                let parent = stack.last ?? top
                let node = parent.add(attributes["TEXT"] ?? "")
                node.isCollapsed = attributes["FOLDED"] == "true"
                stack.append(node)
            case "richcontent" where attributes["TYPE"] == "NODE" && !stack.isEmpty:
                richDepth = 1
                richText = ""
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            if richDepth > 0 {
                richDepth -= 1
                if richDepth == 0, let node = stack.last, node.text.isEmpty {
                    node.text = richText
                        .components(separatedBy: "\n")
                        .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                }
                return
            }
            if name == "node" { _ = stack.popLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if richDepth > 0 { richText += string }
        }
    }
}
