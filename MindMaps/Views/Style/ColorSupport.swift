import SwiftUI
import AppKit

extension Color {
    /// "#RRGGBB" (bzw. mit Deckkraft "#RRGGBBAA") im sRGB-Farbraum.
    var hexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGBAColor(red: Double(color.redComponent), green: Double(color.greenComponent),
                         blue: Double(color.blueComponent), alpha: Double(color.alphaComponent)).hexString
    }
}

/// Merkt sich einen kopierten Knotenstil (⌘ C in der Map bzw. Format › Stil kopieren; einsetzen mit ⌘ R).
enum StyleClipboard {
    static let notification = Notification.Name("MindMapsStyleClipboardChanged")

    static var style: NodeStyle? {
        didSet { NotificationCenter.default.post(name: notification, object: nil) }
    }
}

/// Farbfeld (Farbfenster von macOS). Die Farbe wird erst übernommen, wenn man kurz nicht mehr zieht –
/// so entsteht ein Rückgängig-Schritt statt vieler.
struct DebouncedColorWell: View {
    let title: String
    let hex: String
    let onCommit: (String) -> Void

    @State private var color = Color.gray
    @State private var pending: DispatchWorkItem?

    var body: some View {
        ColorPicker(title, selection: Binding(get: { color }, set: { newColor in
            color = newColor
            commitLater(newColor)
        }), supportsOpacity: false)
        .labelsHidden()
        .onAppear { color = Color(hex: hex) }
        .onChange(of: hex) { _, value in color = Color(hex: value) }
    }

    private func commitLater(_ newColor: Color) {
        pending?.cancel()
        guard let value = newColor.hexString else { return }
        let work = DispatchWorkItem { onCommit(value) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// Farbauswahl mit Vorschlägen (ein Klick = ein Rückgängig-Schritt), freier Farbe und „Standard“.
struct ColorChooser: View {
    let title: String
    /// Aktuelle Farbe (eigene oder aus dem Thema).
    let hex: String
    /// Ist die Farbe selbst gesetzt? Dann gibt es „Standard“.
    let isCustom: Bool
    let suggestions: [String]
    let onPick: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                if isCustom {
                    Button("Standard") { onPick(nil) }
                        .buttonStyle(.link)
                        .font(.caption)
                        .help("Farbe aus dem Thema verwenden")
                }
                DebouncedColorWell(title: title, hex: hex) { onPick($0) }
            }
            if !suggestions.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Button {
                            onPick(suggestion)
                        } label: {
                            Circle()
                                .fill(Color(hex: suggestion))
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(Color.primary.opacity(sameColor(suggestion) ? 0.9 : 0.15),
                                                         lineWidth: sameColor(suggestion) ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .help(suggestion)
                    }
                }
            }
        }
    }

    private func sameColor(_ other: String) -> Bool {
        RGBAColor(hex: other) == RGBAColor(hex: hex)
    }
}

/// Kleines Bild einer Knotenform (für die Auswahl im Inspektor und im Menü).
struct ShapeIcon: View {
    let shape: Theme.NodeShape
    var color: Color = .accentColor

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 3)
            let frame: CGRect
            switch shape {
            case .circle, .square:
                let side = min(rect.width, rect.height)
                frame = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            default:
                frame = rect
            }
            let outline = ShapeGeometry.outline(shape, in: frame)
            if outline.isEmpty {
                // Linie bzw. Eingebettet: nur Text (angedeutet) und ggf. Linie darunter.
                var text = Path()
                text.addRoundedRect(in: CGRect(x: frame.minX + 4, y: frame.midY - 3, width: frame.width - 8, height: 5),
                                    cornerSize: CGSize(width: 2, height: 2))
                context.fill(text, with: .color(color.opacity(0.45)))
                if shape == .line {
                    context.stroke(Path(elements: ShapeGeometry.underline(frame)), with: .color(color), lineWidth: 2)
                }
            } else {
                let path = Path(elements: outline)
                context.fill(path, with: .color(color.opacity(0.15)))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
            }
        }
    }
}
