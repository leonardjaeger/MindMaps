import Foundation

// Sprachen (M12): Deutsch ist die Ausgangssprache – die deutschen Texte im Code sind zugleich die Schlüssel.
// Die englischen Übersetzungen stehen in `Resources/en.lproj/Localizable.strings`.
// Texte direkt in SwiftUI (`Text("…")`, `Button("…")`) übersetzt SwiftUI selbst mit derselben Tabelle;
// alle anderen Texte laufen über `L(…)`.

/// Übersetzter Text für die Sprache des Macs (ohne Übersetzung: der deutsche Text).
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Übersetzter Text mit Platzhaltern: `%@` der Reihe nach, in Übersetzungen auch `%1$@`, `%2$@` …
/// Beispiel: `L("„%@“ gibt es an diesem Ort schon.", name)`.
func L(_ key: String, _ arguments: String...) -> String {
    Localization.fill(L(key), arguments)
}

enum Localization {
    /// Setzt die Werte in die Platzhalter ein. Bewusst ohne `String(format:)` – das braucht auf
    /// Linux (Tests) andere Argumenttypen und stolpert über Prozentzeichen in Knotentexten.
    static func fill(_ template: String, _ arguments: [String]) -> String {
        var result = ""
        var next = 0
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            guard character == "%" else {
                result.append(character)
                index = template.index(after: index)
                continue
            }
            let rest = template[template.index(after: index)...]
            if rest.hasPrefix("%") {
                result.append("%")
                index = template.index(index, offsetBy: 2)
            } else if rest.hasPrefix("@") {
                result += next < arguments.count ? arguments[next] : ""
                next += 1
                index = template.index(index, offsetBy: 2)
            } else if let dollar = rest.firstIndex(of: "$"), rest[rest.index(after: dollar)...].hasPrefix("@"),
                      let position = Int(rest[..<dollar]), position >= 1 {
                result += position <= arguments.count ? arguments[position - 1] : ""
                index = template.index(dollar, offsetBy: 2)
            } else {
                result.append(character)
                index = template.index(after: index)
            }
        }
        return result
    }

    /// Sprache der Oberfläche („de“ oder „en“).
    static var language: String {
        Bundle.main.preferredLocalizations.first ?? "de"
    }
}
