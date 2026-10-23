import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Bilder eines Dokuments zum Zeichnen (einmal dekodiert, dann zwischengespeichert).
/// Die Namen sind eindeutig (UUID), der Inhalt zu einem Namen ändert sich nie – daher darf der
/// Zwischenspeicher über Änderungen des Dokuments hinweg bestehen bleiben.
final class AssetImages {
    private let lookup: (String) -> Data?
    private var cache: [String: NSImage] = [:]

    init(_ assets: [String: Data]) {
        lookup = { assets[$0] }
    }

    /// Liest die Bilder bei Bedarf aus dem Dokument (für die geöffnete Map).
    init(lookup: @escaping (String) -> Data?) {
        self.lookup = lookup
    }

    func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let data = lookup(name), let image = NSImage(data: data) else { return nil }
        cache[name] = image
        return image
    }

    /// Nur Base64 für den SVG-Export.
    func dataURI(_ name: String) -> String? {
        guard let data = lookup(name) else { return nil }
        let mime = name.hasSuffix(".png") ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    static let empty = AssetImages([:])
}

/// Bilder für Knoten vorbereiten: große Fotos verkleinern, passendes Format wählen.
enum ImageImport {
    /// Längste Seite der gespeicherten Datei in Pixeln.
    static let maxPixels: CGFloat = 1600
    /// Anfangsbreite in der Map (Punkte).
    static let defaultWidth: CGFloat = 220

    struct Prepared {
        let data: Data
        let fileExtension: String
        /// Anzeigegröße in Punkten
        let size: CGSize
    }

    static func prepare(_ data: Data) -> Prepared? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              pixelWidth > 0, pixelHeight > 0 else { return nil }

        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // Drehung aus Fotos beachten
            kCGImageSourceThumbnailMaxPixelSize: min(max(pixelWidth, pixelHeight), maxPixels),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let output = NSMutableData()
        let type = hasAlpha ? UTType.png : UTType.jpeg
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let quality: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, (hasAlpha ? nil : quality as CFDictionary))
        guard CGImageDestinationFinalize(destination) else { return nil }

        let width = min(defaultWidth, CGFloat(image.width))
        let height = (width * CGFloat(image.height) / CGFloat(image.width)).rounded()
        return Prepared(data: output as Data, fileExtension: hasAlpha ? "png" : "jpg",
                        size: CGSize(width: width.rounded(), height: max(height, 1)))
    }

    /// Bild aus einer Datei, aus Fotos oder aus der Zwischenablage (per Drag & Drop geliefert).
    static func loadData(from provider: NSItemProvider, completion: @escaping (Data?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                completion(url.flatMap { try? Data(contentsOf: $0) })
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                completion(data)
            }
        } else {
            completion(nil)
        }
    }

    /// Dateiauswahl (auch Fotos-Mediathek über die Seitenleiste „Fotos“).
    @MainActor
    static func chooseFile() -> Data? {
        let panel = NSOpenPanel()
        panel.title = L("Bild einfügen")
        panel.prompt = L("Einfügen")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }
}
