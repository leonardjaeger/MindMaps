import Foundation

/// Was VoiceOver über einen Knoten sagt (M12): der Text als Name, dazu Ebene, Unterknoten, Aufgabe,
/// Notiz, Link, Bild, Formel und Tags – in der Sprache der Oberfläche.
enum NodeSpeech {
    struct Facts: Equatable {
        var depth: Int
        /// Anzahl der direkten Unterknoten (`nil` = unbekannt, nur „hat Unterknoten“).
        var childCount: Int?
        var hasChildren: Bool
        var isCollapsed: Bool
        /// Eigene Aufgabe mit ihrem Stand (bei Unteraufgaben: deren Stand).
        var task: TaskStatus?
        /// Fortschritt der Aufgaben darunter, wenn der Knoten selbst keine Aufgabe ist.
        var progress: (done: Int, total: Int)?
        var hasNote = false
        var hasLink = false
        var hasImage = false
        var hasFormula = false
        var tags: [String] = []

        static func == (a: Facts, b: Facts) -> Bool {
            a.depth == b.depth && a.childCount == b.childCount && a.hasChildren == b.hasChildren
                && a.isCollapsed == b.isCollapsed && a.task == b.task
                && a.progress?.done == b.progress?.done && a.progress?.total == b.progress?.total
                && a.hasNote == b.hasNote && a.hasLink == b.hasLink && a.hasImage == b.hasImage
                && a.hasFormula == b.hasFormula && a.tags == b.tags
        }
    }

    static func facts(of node: Node, depth: Int) -> Facts {
        let progress = node.taskProgress
        return Facts(depth: depth, childCount: node.children.count, hasChildren: !node.children.isEmpty,
                     isCollapsed: node.isCollapsed && !node.children.isEmpty,
                     task: node.task != nil ? node.taskStatus : nil,
                     progress: node.task == nil && progress.total > 0 ? progress : nil,
                     hasNote: !node.note.isEmpty, hasLink: !node.link.isEmpty,
                     hasImage: node.image != nil, hasFormula: !node.formula.isEmpty, tags: node.tags)
    }

    static func facts(of row: OutlineRow) -> Facts {
        Facts(depth: row.depth, childCount: nil, hasChildren: row.hasChildren,
              isCollapsed: row.isCollapsed && row.hasChildren,
              task: row.hasTaskMark ? row.taskStatus : nil,
              progress: row.hasTaskMark ? nil : row.taskProgress,
              hasNote: row.hasNote, hasLink: row.hasLink, tags: row.tags)
    }

    /// Name des Knotens für VoiceOver.
    static func label(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L("Ohne Text") : trimmed
    }

    /// Einzelheiten, z. B. „Ebene 2, 3 Unterknoten, Aufgabe offen, mit Notiz, Tags: Wichtig“.
    static func details(_ facts: Facts) -> String {
        var parts: [String] = [facts.depth == 0 ? L("Hauptknoten") : L("Ebene %@", "\(facts.depth)")]
        if facts.hasChildren {
            if facts.isCollapsed {
                parts.append(L("eingeklappt"))
            } else if let count = facts.childCount {
                parts.append(count == 1 ? L("1 Unterknoten") : L("%@ Unterknoten", "\(count)"))
            } else {
                parts.append(L("hat Unterknoten"))
            }
        }
        switch facts.task {
        case .open?: parts.append(L("Aufgabe offen"))
        case .partial?: parts.append(L("Aufgabe teilweise erledigt"))
        case .done?: parts.append(L("Aufgabe erledigt"))
        case nil:
            if let progress = facts.progress, progress.total > 0 {
                parts.append(L("%@ von %@ Aufgaben erledigt", "\(progress.done)", "\(progress.total)"))
            }
        }
        if facts.hasNote { parts.append(L("mit Notiz")) }
        if facts.hasLink { parts.append(L("mit Link")) }
        if facts.hasImage { parts.append(L("mit Bild")) }
        if facts.hasFormula { parts.append(L("mit Formel")) }
        if !facts.tags.isEmpty { parts.append(L("Tags: %@", facts.tags.joined(separator: ", "))) }
        return parts.joined(separator: ", ")
    }

    /// Ganzer Satz, z. B. für eine Ansage beim Auswählen.
    static func sentence(for node: Node, depth: Int) -> String {
        label(node.text) + ", " + details(facts(of: node, depth: depth))
    }
}

/// Kontrast nach WCAG 2 (M12): Text braucht mindestens 4,5 : 1, Zweige und Symbole 3 : 1.
enum ColorContrast {
    static let textMinimum = 4.5
    static let graphicsMinimum = 3.0

    /// Relative Leuchtdichte (0 = schwarz, 1 = weiß).
    static func luminance(_ color: RGBAColor) -> Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    /// Kontrastverhältnis zweier Farben (1 … 21), `nil` bei ungültigen Farben.
    static func ratio(_ a: String, _ b: String) -> Double? {
        guard let first = RGBAColor(hex: a), let second = RGBAColor(hex: b) else { return nil }
        let la = luminance(first), lb = luminance(second)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    struct Issue: Equatable {
        /// Was zu schwach ist, z. B. „Text auf Knoten“.
        let what: String
        let ratio: Double
        let minimum: Double
        let dark: Bool

        /// „Text auf Knoten (dunkel): 3,1 : 1 – nötig sind 4,5 : 1“
        var description: String {
            let mode = dark ? L("dunkel") : L("hell")
            return L("%@ (%@): %@ : 1 – nötig sind %@ : 1", what, mode, Self.format(ratio), Self.format(minimum))
        }

        static func format(_ value: Double) -> String {
            let rounded = (value * 10).rounded(.down) / 10
            let text = String(Int(rounded)) + "." + String(Int((rounded * 10).rounded()) % 10)
            return Localization.language == "de" ? text.replacingOccurrences(of: ".", with: ",") : text
        }
    }

    /// Zu schwache Kontraste eines Themas (hell und dunkel).
    static func issues(in theme: Theme) -> [Issue] {
        var result: [Issue] = []
        for dark in [false, true] {
            let palette = theme.palette(dark: dark)
            func check(_ what: String, _ a: String, _ b: String, _ minimum: Double) {
                if let value = ratio(a, b), value < minimum {
                    result.append(Issue(what: what, ratio: value, minimum: minimum, dark: dark))
                }
            }
            check(L("Text im Hauptknoten"), palette.rootText, palette.rootFill, textMinimum)
            check(L("Text auf Knoten"), palette.nodeText, palette.nodeFill, textMinimum)
            check(L("Text auf dem Hintergrund"), palette.nodeText, palette.canvas, textMinimum)
            for (index, branch) in palette.branches.enumerated() {
                check(L("Zweigfarbe %@", "\(index + 1)"), branch, palette.canvas, graphicsMinimum)
                if theme.nodeFill == .tinted, let base = RGBAColor(hex: palette.nodeFill),
                   let tint = RGBAColor(hex: branch) {
                    let fill = base.mixed(with: tint, amount: 0.22).hexString
                    check(L("Text auf getönter Fläche %@", "\(index + 1)"), palette.nodeText, fill, textMinimum)
                }
            }
        }
        return result
    }

    /// Kontrast eines einzelnen Knotens: Text auf seiner Fläche (bzw. dem Hintergrund der Map).
    static func textIssue(_ look: NodeAppearance, canvas: String) -> Double? {
        let background = look.fill ?? canvas
        guard let value = ratio(look.text, background), value < textMinimum else { return nil }
        return value
    }
}
