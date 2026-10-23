import Foundation

/// RTF: Hauptknoten als Titel, Hauptäste als Überschriften, darunter eingerückte Aufzählung.
/// Wird von Hand geschrieben (kein AppKit nötig), Umlaute und Emoji als \u-Zeichen.
enum RTFFormat {

    static func export(_ root: Node) -> String {
        var out = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss\fcharset0 Helvetica;}}"# + "\n"
        out += #"{\colortbl;\red8\green102\blue227;}"# + "\n"
        out += #"\viewkind0\f0\fs24"# + "\n"
        out += #"{\pard\sa240\b\fs40\cf1 "# + escape(root.text) + #"\par}"# + "\n"
        for child in root.children {
            out += #"{\pard\sb240\sa120\b\fs30 "# + escape(child.text) + #"\par}"# + "\n"
            addList(child.children, level: 0, to: &out)
        }
        out += "}\n"
        return out
    }

    private static func addList(_ nodes: [Node], level: Int, to out: inout String) {
        // Einzug in Twips (1/20 pt): 0,5 cm je Ebene, Aufzählungszeichen hängt links heraus.
        let left = 360 + level * 360
        let bullet = level % 2 == 0 ? #"\bullet"# : #"\endash"#
        for node in nodes {
            out += "{\\pard\\li\(left)\\fi-240\\sa60 \(bullet)\\tab " + escape(node.text) + #"\par}"# + "\n"
            addList(node.children, level: level + 1, to: &out)
        }
    }

    /// Steuerzeichen maskieren, alles außerhalb von ASCII als \uN? (UTF-16, vorzeichenbehaftet).
    static func escape(_ text: String) -> String {
        var out = ""
        for unit in text.utf16 {
            switch unit {
            case 0x5C: out += #"\\"#
            case 0x7B: out += #"\{"#
            case 0x7D: out += #"\}"#
            case 0x0A: out += #"\line "#
            case 0x09: out += #"\tab "#
            case 0x0D: break
            case 0x20..<0x80: out.unicodeScalars.append(Unicode.Scalar(unit)!)
            case 0..<0x20: break
            default: out += "\\u\(Int16(bitPattern: unit))?"
            }
        }
        return out
    }
}
