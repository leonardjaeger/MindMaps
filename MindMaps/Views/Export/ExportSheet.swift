import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Export-Dialog (Ablage › Exportieren …, ⇧ ⌘ E): Format wählen, dann sichern oder als Kopie senden.
struct ExportSheet: View {
    let data: MindMapDocumentData
    /// Bilder des Dokuments (M7)
    var assets: [String: Data] = [:]
    /// Vorschlag für den Dateinamen (ohne Endung).
    let baseName: String

    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportFormat") private var format: ExportFormat = .pdf
    @AppStorage("exportTransparent") private var transparent = false
    @AppStorage("exportPDFPaging") private var paging: PDFPaging = .a4
    @AppStorage("exportPNGScale") private var pngScale = 2
    @State private var errorMessage: String?
    @State private var shareAnchor = ShareAnchor()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exportieren").font(.title2.bold())

            Form {
                Picker("Format", selection: $format) {
                    Section("Text") {
                        ForEach(ExportFormat.textFormats) { Text($0.title).tag($0) }
                    }
                    Section("Bild") {
                        ForEach(ExportFormat.imageFormats) { Text($0.title).tag($0) }
                    }
                }

                if format == .pdf {
                    Picker("Seiten", selection: $paging) {
                        ForEach(PDFPaging.allCases) { Text($0.title).tag($0) }
                    }
                }
                if format == .png {
                    Picker("Auflösung", selection: $pngScale) {
                        Text("1×").tag(1)
                        Text("2× (Retina)").tag(2)
                        Text("3×").tag(3)
                    }
                }
                if format == .png || format == .pdf {
                    Toggle("Transparenter Hintergrund", isOn: $transparent)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 150)

            Text(format.explanation)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }

            HStack {
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    share()
                } label: {
                    Label("Kopie senden …", systemImage: "square.and.arrow.up")
                }
                .background(ShareAnchorView(anchor: shareAnchor))
                .help("Als E-Mail, Nachricht, AirDrop … verschicken")
                Button("Exportieren …") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .alert("Export fehlgeschlagen", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var options: ExportOptions {
        ExportOptions(transparent: transparent, pngScale: CGFloat(pngScale), paging: paging)
    }

    /// Größe bzw. Seitenzahl, damit man vorher weiß, was herauskommt.
    private var detail: String? {
        switch format {
        case .png:
            let size = MapImageExporter.pngPixelSize(data, scale: CGFloat(pngScale))
            return L("%@ × %@ Pixel", "\(Int(size.width))", "\(Int(size.height))")
        case .pdf:
            let pages = MapImageExporter.tiling(data, paging: paging)
            let percent = Int((pages.scale * 100).rounded())
            if paging == .singlePage {
                return L("1 Seite, %@ × %@ pt, Maßstab %@ %%", "\(Int(pages.pageSize.width))", "\(Int(pages.pageSize.height))", "\(percent)")
            }
            let count = pages.tiles.count
            let orientation = pages.isLandscape ? "quer" : "hoch"
            return count == 1
                ? L("1 Seite A4 %@, Maßstab %@ %%", orientation, "\(percent)")
                : L("%@ Seiten A4 %@ (%@ × %@), Maßstab %@ %%", "\(count)", orientation, "\(pages.rows)", "\(pages.columns)", "\(percent)")
        default:
            return nil
        }
    }

    private var fileName: String { baseName + "." + format.fileExtension }

    private func makeWrapper() -> FileWrapper? {
        do {
            return try MapImageExporter.fileWrapper(for: data, assets: assets, format: format, options: options,
                                                    title: baseName)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.title = L("Exportieren als %@", format.title)
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url, let wrapper = makeWrapper() else { return }
        do {
            try ExportFiles.write(wrapper, to: url)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func share() {
        guard let wrapper = makeWrapper() else { return }
        do {
            let url = try ExportFiles.temporaryURL(named: fileName)
            try ExportFiles.write(wrapper, to: url)
            guard let view = shareAnchor.view else { return }
            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Schreiben von Export-Dateien (auch Pakete wie TextBundle) – ersetzt eine vorhandene Datei sicher.
enum ExportFiles {
    static func write(_ wrapper: FileWrapper, to url: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("MindMaps-Export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let temp = staging.appendingPathComponent(url.lastPathComponent)
        try wrapper.write(to: temp, options: [], originalContentsURL: nil)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: url)
        }
    }

    /// Eigener Ordner je Versand, damit der Dateiname genau stimmt.
    static func temporaryURL(named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindMaps-Senden", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(name)
    }
}

/// Merkt sich die Ansicht des Knopfs „Kopie senden“, damit das Teilen-Menü dort aufgeht.
final class ShareAnchor {
    weak var view: NSView?
}

struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}
