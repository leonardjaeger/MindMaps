import Cocoa
import Quartz
import UniformTypeIdentifiers

/// Quick-Look-Vorschau für `.mindmaps` (Leertaste im Finder).
///
/// Zeigt das Vorschaubild, das MindMaps beim Sichern unter `QuickLook/Preview.png` ins Paket legt.
/// Ältere Dateien ohne Bild bekommen die Gliederung als einfache HTML-Seite.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let package = request.fileURL
        let pngURL = package.appendingPathComponent("QuickLook/Preview.png")

        if let png = try? Data(contentsOf: pngURL), let image = NSImage(data: png) {
            return QLPreviewReply(dataOfContentType: .png, contentSize: image.size) { _ in png }
        }

        let json = try Data(contentsOf: package.appendingPathComponent("document.json"))
        let html = OutlineHTML.page(from: json, title: package.deletingPathExtension().lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 720, height: 900)) { reply in
            reply.stringEncoding = .utf8
            return Data(html.utf8)
        }
    }
}

/// Gliederung als HTML – bewusst ohne Code aus der App, damit die Erweiterung klein und unabhängig bleibt.
enum OutlineHTML {
    private struct PreviewNode: Decodable {
        let text: String?
        let children: [PreviewNode]?
    }

    private struct PreviewDocument: Decodable {
        let root: PreviewNode
    }

    static func page(from json: Data, title: String) -> String {
        guard let document = try? JSONDecoder().decode(PreviewDocument.self, from: json) else {
            return wrap(title: title, body: "<p>Die Mindmap konnte nicht gelesen werden.</p>")
        }
        let rootText = escape(document.root.text ?? "")
        let list = (document.root.children ?? []).map(item).joined()
        return wrap(title: title, body: "<h1>\(rootText)</h1><ul>\(list)</ul>")
    }

    private static func item(_ node: PreviewNode) -> String {
        let children = node.children ?? []
        let sublist = children.isEmpty ? "" : "<ul>\(children.map(item).joined())</ul>"
        let text = (node.text ?? "").isEmpty ? "…" : escape(node.text ?? "")
        return "<li>\(text)\(sublist)</li>"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func wrap(title: String, body: String) -> String {
        """
        <!doctype html><html lang="de"><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        :root { color-scheme: light dark; }
        body { font: 15px -apple-system, sans-serif; margin: 32px; }
        h1 { font-size: 22px; color: #0866E3; }
        ul { list-style: none; padding-left: 18px; border-left: 2px solid #0866E344; margin: 4px 0; }
        li { margin: 4px 0; }
        </style></head><body>\(body)</body></html>
        """
    }
}
