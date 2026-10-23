import Foundation

/// Text-Exporte als Datei bzw. Paket (Bild-Exporte macht `MapImageExporter`).
enum TextExporter {
    static func fileWrapper(for data: MindMapDocumentData, format: ExportFormat) -> FileWrapper? {
        let root = data.root
        func file(_ text: String) -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
        switch format {
        case .markdown: return file(MarkdownFormat.export(root))
        case .opml: return file(OPMLFormat.export(root))
        case .plainText: return file(PlainTextFormat.export(root))
        case .rtf: return file(RTFFormat.export(root))
        case .freeMind: return file(FreeMindFormat.export(root))
        case .textBundle: return TextBundleFormat.fileWrapper(for: root)
        case .png, .pdf, .svg: return nil
        }
    }
}

/// Verteilt eine große Mindmap für den PDF-Export auf A4-Seiten.
///
/// Passt die Map lesbar (mindestens 60 %) auf eine Seite, bleibt es bei einer Seite.
/// Sonst wird sie in 75 % Größe auf ein Raster aus Seiten gelegt (mit etwas Überlappung zum Zusammenkleben);
/// Seiten ohne Inhalt fallen weg. Hoch- oder Querformat: was weniger Seiten braucht.
struct PageTiling: Equatable {
    struct Tile: Equatable {
        /// Ausschnitt in Map-Koordinaten.
        var rect: CGRect
        var row: Int
        var column: Int
    }

    var pageSize: CGSize
    var margin: CGFloat
    var scale: CGFloat
    var rows: Int
    var columns: Int
    var tiles: [Tile]

    static let a4Portrait = CGSize(width: 595, height: 842)

    var isLandscape: Bool { pageSize.width > pageSize.height }

    /// Größte Seitenlänge, die PDF-Programme zuverlässig anzeigen (200 Zoll).
    static let maximumPageSide: CGFloat = 14_400

    /// Eine Seite genau in Größe der Map (Maßstab 100 %, bei riesigen Maps kleiner).
    static func singlePage(content: CGRect) -> PageTiling {
        let scale = min(1, maximumPageSide / max(content.width, content.height, 1))
        return PageTiling(pageSize: CGSize(width: content.width * scale, height: content.height * scale),
                          margin: 0, scale: scale, rows: 1, columns: 1,
                          tiles: [Tile(rect: content, row: 0, column: 0)])
    }

    static func a4(content: CGRect,
                   occupied: [CGRect],
                   margin: CGFloat = 28,
                   minimumFitScale: CGFloat = 0.6,
                   tileScale: CGFloat = 0.75,
                   overlap: CGFloat = 16) -> PageTiling {
        let portrait = a4Portrait
        let landscape = CGSize(width: portrait.height, height: portrait.width)
        let candidates = [landscape, portrait].map { page in
            tiling(content: content, occupied: occupied, page: page, margin: margin,
                   minimumFitScale: minimumFitScale, tileScale: tileScale, overlap: overlap)
        }
        return candidates.min { a, b in
            if a.tiles.count != b.tiles.count { return a.tiles.count < b.tiles.count }
            return a.scale > b.scale
        }!
    }

    private static func tiling(content: CGRect, occupied: [CGRect], page: CGSize, margin: CGFloat,
                               minimumFitScale: CGFloat, tileScale: CGFloat, overlap: CGFloat) -> PageTiling {
        let printable = CGSize(width: page.width - 2 * margin, height: page.height - 2 * margin)
        let fit = min(printable.width / max(content.width, 1), printable.height / max(content.height, 1))

        if fit >= minimumFitScale {
            let scale = min(fit, 1)
            let size = CGSize(width: printable.width / scale, height: printable.height / scale)
            let rect = CGRect(x: content.midX - size.width / 2, y: content.midY - size.height / 2,
                              width: size.width, height: size.height)
            return PageTiling(pageSize: page, margin: margin, scale: scale, rows: 1, columns: 1,
                              tiles: [Tile(rect: rect, row: 0, column: 0)])
        }

        let tileW = printable.width / tileScale
        let tileH = printable.height / tileScale
        let columns = max(1, Int(ceil((content.width - overlap) / (tileW - overlap))))
        let rows = max(1, Int(ceil((content.height - overlap) / (tileH - overlap))))
        let gridW = CGFloat(columns) * tileW - CGFloat(columns - 1) * overlap
        let gridH = CGFloat(rows) * tileH - CGFloat(rows - 1) * overlap
        let origin = CGPoint(x: content.midX - gridW / 2, y: content.midY - gridH / 2)

        var tiles: [Tile] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: origin.x + CGFloat(column) * (tileW - overlap),
                                  y: origin.y + CGFloat(row) * (tileH - overlap),
                                  width: tileW, height: tileH)
                if occupied.isEmpty || occupied.contains(where: { $0.intersects(rect) }) {
                    tiles.append(Tile(rect: rect, row: row, column: column))
                }
            }
        }
        return PageTiling(pageSize: page, margin: margin, scale: tileScale, rows: rows, columns: columns, tiles: tiles)
    }
}
