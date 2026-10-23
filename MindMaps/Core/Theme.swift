import Foundation

/// Farben eines Themes für hellen oder dunklen Modus (Hex-Werte wie "#0866E3").
struct ThemePalette: Codable, Equatable {
    var canvas: String
    var rootFill: String
    var rootText: String
    var nodeFill: String
    var nodeText: String
    var branches: [String]

    /// Farbe für den Hauptast mit Index `index` (Farben wiederholen sich).
    func branchColor(at index: Int) -> String {
        guard !branches.isEmpty else { return nodeText }
        return branches[((index % branches.count) + branches.count) % branches.count]
    }
}

struct Theme: Codable, Identifiable, Equatable {
    enum BranchStyle: String, Codable, CaseIterable { case curved, angled }
    enum BranchWidth: String, Codable, CaseIterable { case uniform, tapered, uniformThick = "uniform-thick" }
    /// Die 10 Knotenformen (M8), in der Reihenfolge der Auswahl im Inspektor.
    enum NodeShape: String, Codable, CaseIterable {
        case circle, square, rectangle, rounded, pill, cloud, line, embedded, hexagon, octagon
    }
    enum NodeFillMode: String, Codable, CaseIterable { case plain = "none", tinted }
    enum Font: String, Codable, CaseIterable { case system, rounded, serif, systemBold = "system-bold", monospaced }

    var id: String
    var name: String
    var description: String
    var branchStyle: BranchStyle
    var branchWidth: BranchWidth
    var nodeShape: NodeShape
    var nodeFill: NodeFillMode
    var font: Font
    var light: ThemePalette
    var dark: ThemePalette

    func palette(dark isDark: Bool) -> ThemePalette {
        isDark ? dark : light
    }

    /// Eingebautes Ersatz-Theme, falls Themes.json fehlt oder defekt ist.
    static let fallback = Theme(
        id: "blau", name: L("MindMaps Blau"), description: L("Standard-Thema"),
        branchStyle: .curved, branchWidth: .tapered, nodeShape: .rounded, nodeFill: .plain, font: .system,
        light: ThemePalette(canvas: "#F6F8FB", rootFill: "#0866E3", rootText: "#FFFFFF",
                            nodeFill: "#FFFFFF", nodeText: "#1B2330",
                            branches: ["#0866E3", "#0E8C9B", "#6A4BD8", "#C2410C", "#1F8A4C", "#B4236B"]),
        dark: ThemePalette(canvas: "#12161D", rootFill: "#1F6FE5", rootText: "#FFFFFF",
                           nodeFill: "#1B212B", nodeText: "#E8EDF5",
                           branches: ["#5CA1FF", "#3CC7D6", "#A58BFF", "#FF8A4C", "#4FD18B", "#FF6FAE"]))
}

/// Inhalt von Themes.json.
struct ThemeCatalog: Codable {
    var formatVersion: Int
    var themes: [Theme]

    static func decode(_ data: Data) throws -> ThemeCatalog {
        try JSONDecoder().decode(ThemeCatalog.self, from: data)
    }

    func theme(withID id: String) -> Theme {
        themes.first { $0.id == id } ?? themes.first ?? .fallback
    }
}

/// RGBA-Farbe aus einem Hex-String ("#RRGGBB" oder "#RRGGBBAA"), Werte 0…1.
struct RGBAColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            red = Double((v >> 16) & 0xFF) / 255
            green = Double((v >> 8) & 0xFF) / 255
            blue = Double(v & 0xFF) / 255
            alpha = 1
        } else {
            red = Double((v >> 24) & 0xFF) / 255
            green = Double((v >> 16) & 0xFF) / 255
            blue = Double((v >> 8) & 0xFF) / 255
            alpha = Double(v & 0xFF) / 255
        }
    }

    /// Mischt zwei Farben (t = 0 → self, t = 1 → other).
    func mixed(with other: RGBAColor, amount t: Double) -> RGBAColor {
        RGBAColor(red: red + (other.red - red) * t,
                  green: green + (other.green - green) * t,
                  blue: blue + (other.blue - blue) * t,
                  alpha: alpha + (other.alpha - alpha) * t)
    }
}
