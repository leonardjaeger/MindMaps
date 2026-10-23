import SwiftUI
import AppKit
import PDFKit

/// Drucken (⌘ P): Optionen wählen, dann das Druckfenster von macOS (Drucker, Kopien, Vorschau).
///
/// Gedruckt wird dasselbe Bild wie beim PDF-Export – gezeichnet von `MapRenderer` wie auf dem Bildschirm.
struct PrintSheet: View {
    let data: MindMapDocumentData
    let assets: [String: Data]
    let title: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("printPaging") private var paging: PDFPaging = .a4
    @AppStorage("printBackground") private var background = true
    @State private var dark = false

    var body: some View {
        let tiling = MapImageExporter.tiling(data, paging: paging)
        VStack(alignment: .leading, spacing: 16) {
            Text("Drucken").font(.title3.weight(.semibold))
            Form {
                Picker("Seiten", selection: $paging) {
                    Text("Auf eine Seite verkleinern").tag(PDFPaging.singlePage)
                    Text("A4, gut lesbar (ggf. mehrere Seiten)").tag(PDFPaging.a4)
                }
                .pickerStyle(.radioGroup)
                Toggle("Hintergrundfarbe drucken", isOn: $background)
                if colorScheme == .dark {
                    Toggle("Dunkles Erscheinungsbild (wie auf dem Bildschirm)", isOn: $dark)
                }
            }
            Text(summary(tiling))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Drucken …", action: print)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func summary(_ tiling: PageTiling) -> String {
        switch paging {
        case .singlePage:
            return L("Die ganze Mindmap auf einem Blatt – das Druckfenster passt sie an das Papier an.")
        case .a4:
            let pages = tiling.tiles.count
            let format = tiling.isLandscape ? L("Querformat") : L("Hochformat")
            if pages == 1 {
                return L("1 Seite A4, %@, Maßstab %@ %%.", format, "\(Int((tiling.scale * 100).rounded()))")
            }
            return L("%@ Seiten A4 im %@, Maßstab %@ %% (%@ Reihen × %@ Spalten, mit Überlappung zum Zusammenkleben).",
                     "\(pages)", format, "\(Int((tiling.scale * 100).rounded()))", "\(tiling.rows)", "\(tiling.columns)")
        }
    }

    private func print() {
        // Erst das Blatt schließen, dann das Druckfenster am Dokumentfenster öffnen.
        let job = (data, assets, paging, background, dark && colorScheme == .dark, title)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            do {
                try MapPrinter.print(job.0, assets: job.1, paging: job.2, background: job.3, dark: job.4, title: job.5)
            } catch {
                let alert = NSAlert()
                alert.messageText = error.localizedDescription
                alert.runModal()
            }
        }
    }
}

/// Druckt eine Mindmap über das PDF, das auch der Export erzeugt.
@MainActor
enum MapPrinter {
    enum PrintError: LocalizedError {
        case failed
        var errorDescription: String? { L("Die Mindmap ließ sich nicht drucken.") }
    }

    static func print(_ data: MindMapDocumentData, assets: [String: Data], paging: PDFPaging,
                      background: Bool, dark: Bool, title: String) throws {
        let pdf = try MapImageExporter.pdf(data, assets: assets, paging: paging, transparent: !background,
                                           title: title, dark: dark)
        guard let document = PDFDocument(data: pdf) else { throw PrintError.failed }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        let tiling = MapImageExporter.tiling(data, paging: paging)
        info.orientation = tiling.isLandscape ? .landscape : .portrait
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            throw PrintError.failed
        }
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
