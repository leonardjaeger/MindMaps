import Foundation

/// Bausteine einer Formel.
indirect enum MathAtom: Equatable {
    enum Kind: Equatable {
        /// Variable, kursiv (x, m, α)
        case variable
        /// Zahl, Klammer, Großbuchstabe griechisch – aufrecht
        case ordinary
        /// + − · × – mit Abstand auf beiden Seiten
        case binary
        /// = < ≤ → – mit etwas mehr Abstand
        case relation
        /// Komma, Semikolon – Abstand danach
        case punctuation
        /// sin, log, lim – aufrecht, kleiner Abstand danach
        case function
    }

    case row([MathAtom])
    case symbol(String, Kind)
    case fraction(MathAtom, MathAtom)
    case scripts(base: MathAtom, sup: MathAtom?, sub: MathAtom?)
    case root(MathAtom, index: MathAtom?)
    /// ∑ ∫ ∏ – groß; `limits`: Grenzen darüber/darunter statt daneben
    case bigOperator(String, limits: Bool)
    case accent(MathAtom, String)
    case text(String)
    /// Abstand in em (Vielfaches der Schriftgröße)
    case space(Double)
}

/// Liest eine Formel in LaTeX-Schreibweise (die gängige Teilmenge für Schule und Studium).
///
/// Unterstützt u. a.: `^` `_` `\frac` `\sqrt[n]{}` griechische Buchstaben, `\cdot \times \pm \leq \geq \neq \approx
/// \infty \to \Rightarrow \in`, `\sum \prod \int \lim`, `\sin \cos \log \ln`, `\vec \hat \bar`, `\text{}`,
/// Abstände `\, \; \quad`. `\left` / `\right` werden ignoriert. Unbekannte Befehle erscheinen als Text.
struct MathParser {
    private let chars: [Character]
    private var index = 0

    init(_ source: String) {
        chars = Array(source)
    }

    static func parse(_ source: String) -> MathAtom {
        var parser = MathParser(source)
        return parser.parseRow(until: nil)
    }

    // MARK: - Zeichen

    private var atEnd: Bool { index >= chars.count }
    private var current: Character? { atEnd ? nil : chars[index] }

    private mutating func skipSpaces() {
        while let c = current, c == " " || c == "\t" || c == "\n" { index += 1 }
    }

    // MARK: - Zeile und Gruppen

    private mutating func parseRow(until terminator: Character?) -> MathAtom {
        var items: [MathAtom] = []
        while true {
            skipSpaces()
            guard let c = current else { break }
            if let terminator, c == terminator { index += 1; break }
            if c == "}" { index += 1; break }       // überzählige Klammer: Gruppe endet
            if c == "^" || c == "_" {
                // Hoch-/Tiefstellung ohne Basis
                let base = items.popLast() ?? .symbol("", .ordinary)
                items.append(parseScripts(base: base))
                continue
            }
            guard var atom = parseAtom() else { continue }
            skipSpaces()
            if let next = current, next == "^" || next == "_" {
                atom = parseScripts(base: atom)
            }
            items.append(atom)
        }
        return items.count == 1 ? items[0] : .row(items)
    }

    private mutating func parseScripts(base: MathAtom) -> MathAtom {
        var sup: MathAtom?
        var sub: MathAtom?
        var base = base
        var limits = false
        if case .bigOperator(let symbol, let wantsLimits) = base {
            limits = wantsLimits
            base = .bigOperator(symbol, limits: wantsLimits)
        }
        if case .symbol(_, .function) = base { limits = true }
        while true {
            skipSpaces()
            guard let c = current, c == "^" || c == "_" else { break }
            index += 1
            let argument = parseArgument()
            if c == "^" { sup = argument } else { sub = argument }
        }
        if limits, case .symbol(let name, .function) = base {
            // lim_{x→0}: Grenze darunter
            return .scripts(base: .bigOperator(name, limits: true), sup: sup, sub: sub)
        }
        return .scripts(base: base, sup: sup, sub: sub)
    }

    /// Ein Argument: `{…}` oder ein einzelnes Zeichen / ein Befehl.
    private mutating func parseArgument() -> MathAtom {
        skipSpaces()
        guard let c = current else { return .row([]) }
        if c == "{" {
            index += 1
            return parseRow(until: "}")
        }
        return parseAtom() ?? .row([])
    }

    /// Inhalt von `{…}` als reiner Text (für \text).
    private mutating func parseRawGroup() -> String {
        skipSpaces()
        guard current == "{" else {
            if let c = current { index += 1; return String(c) }
            return ""
        }
        index += 1
        var depth = 1
        var text = ""
        while let c = current {
            index += 1
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            text.append(c)
        }
        return text
    }

    private mutating func parseOptionalBracket() -> MathAtom? {
        skipSpaces()
        guard current == "[" else { return nil }
        index += 1
        return parseRow(until: "]")
    }

    // MARK: - Einzelne Bausteine

    private mutating func parseAtom() -> MathAtom? {
        guard let c = current else { return nil }
        index += 1
        switch c {
        case "{":
            return parseRow(until: "}")
        case "\\":
            return parseCommand()
        case "a"..."z", "A"..."Z":
            return .symbol(String(c), .variable)
        case "0"..."9", ".":
            var number = String(c)
            while let d = current, d.isASCII, d.isNumber || d == "." {
                number.append(d)
                index += 1
            }
            return .symbol(number, .ordinary)
        case "+", "*":
            return .symbol(c == "*" ? "∗" : "+", .binary)
        case "-":
            return .symbol("−", .binary)
        case "=", "<", ">":
            return .symbol(String(c), .relation)
        case ",", ";":
            return .symbol(String(c), .punctuation)
        case "'":
            return .symbol("′", .ordinary)
        case "~":
            return .space(0.25)
        case "&":
            return .space(0.5)
        default:
            return .symbol(String(c), .ordinary)
        }
    }

    private mutating func parseCommand() -> MathAtom? {
        guard let first = current else { return .symbol("\\", .ordinary) }
        // Ein-Zeichen-Befehle: \, \; \{ \} \| \! \\ usw.
        if !first.isLetter {
            index += 1
            switch first {
            case ",": return .space(0.167)
            case ":", ">": return .space(0.222)
            case ";": return .space(0.278)
            case "!": return .space(-0.167)
            case " ": return .space(0.25)
            case "\\": return .space(0.5)
            case "|": return .symbol("‖", .ordinary)
            default: return .symbol(String(first), .ordinary)
            }
        }
        var name = ""
        while let c = current, c.isLetter {
            name.append(c)
            index += 1
        }
        return atom(forCommand: name)
    }

    private mutating func atom(forCommand name: String) -> MathAtom? {
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let numerator = parseArgument()
            let denominator = parseArgument()
            return .fraction(numerator, denominator)
        case "sqrt":
            let rootIndex = parseOptionalBracket()
            return .root(parseArgument(), index: rootIndex)
        case "text", "textrm", "mathrm", "mbox", "operatorname", "textit", "mathit", "mathbf", "textbf", "mathsf", "mathcal":
            let text = parseRawGroup()
            if name == "operatorname" { return .symbol(text, .function) }
            if name == "mathit" || name == "textit" { return .symbol(text, .variable) }
            return .text(text)
        case "vec", "overrightarrow": return .accent(parseArgument(), "→")
        case "hat", "widehat": return .accent(parseArgument(), "^")
        case "bar", "overline": return .accent(parseArgument(), "¯")
        case "tilde", "widetilde": return .accent(parseArgument(), "~")
        case "dot": return .accent(parseArgument(), "˙")
        case "ddot": return .accent(parseArgument(), "¨")
        case "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "displaystyle", "textstyle",
             "limits", "nolimits":
            skipSpaces()
            if current == "." { index += 1 }
            return nil
        case "quad": return .space(1)
        case "qquad": return .space(2)
        default:
            break
        }
        if let letter = Self.greek[name] {
            let isUpper = name.first?.isUppercase == true
            return .symbol(letter, isUpper ? .ordinary : .variable)
        }
        if let symbol = Self.binaryOperators[name] { return .symbol(symbol, .binary) }
        if let symbol = Self.relations[name] { return .symbol(symbol, .relation) }
        if let symbol = Self.ordinarySymbols[name] { return .symbol(symbol, .ordinary) }
        if let symbol = Self.bigOperators[name] {
            return .bigOperator(symbol, limits: ["sum", "prod", "coprod", "bigcup", "bigcap"].contains(name))
        }
        if Self.functions.contains(name) { return .symbol(name, .function) }
        // Unbekannt: Namen als Text zeigen, damit nichts verschwindet.
        return .text("\\" + name)
    }

    // MARK: - Tabellen

    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ",
        "upsilon": "υ", "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
    ]

    static let binaryOperators: [String: String] = [
        "cdot": "·", "times": "×", "div": "÷", "pm": "±", "mp": "∓", "cup": "∪", "cap": "∩", "circ": "∘",
        "ast": "∗", "oplus": "⊕", "otimes": "⊗", "setminus": "∖", "wedge": "∧", "vee": "∨", "land": "∧", "lor": "∨",
    ]

    static let relations: [String: String] = [
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡",
        "sim": "∼", "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫", "in": "∈", "notin": "∉",
        "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃", "supseteq": "⊇", "to": "→", "rightarrow": "→",
        "leftarrow": "←", "gets": "←", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔",
        "leftrightarrow": "↔", "mapsto": "↦", "implies": "⟹", "iff": "⟺", "perp": "⊥", "parallel": "∥",
        "mid": "∣", "longrightarrow": "⟶", "uparrow": "↑", "downarrow": "↓",
    ]

    static let ordinarySymbols: [String: String] = [
        "infty": "∞", "partial": "∂", "nabla": "∇", "forall": "∀", "exists": "∃", "emptyset": "∅",
        "varnothing": "∅", "hbar": "ℏ", "ell": "ℓ", "degree": "°", "prime": "′", "angle": "∠",
        "triangle": "△", "ldots": "…", "cdots": "⋯", "dots": "…", "neg": "¬", "lnot": "¬", "aleph": "ℵ",
        "Re": "ℜ", "Im": "ℑ", "langle": "⟨", "rangle": "⟩", "lbrace": "{", "rbrace": "}", "lfloor": "⌊",
        "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|", "Vert": "‖", "percent": "%", "checkmark": "✓",
        "square": "□", "star": "⋆", "bullet": "•", "top": "⊤", "bot": "⊥", "N": "ℕ", "Z": "ℤ", "Q": "ℚ",
        "R": "ℝ", "C": "ℂ",
    ]

    static let bigOperators: [String: String] = [
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
        "bigcup": "⋃", "bigcap": "⋂",
    ]

    static let functions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
        "log", "ln", "lg", "exp", "lim", "limsup", "liminf", "min", "max", "sup", "inf", "det", "dim",
        "ker", "deg", "gcd", "arg", "Pr", "mod",
    ]
}
