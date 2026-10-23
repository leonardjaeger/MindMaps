import SwiftUI

/// Zustand von Suchen & Ersetzen in einem Dokumentfenster.
struct FindState: Equatable {
    var isVisible = false
    var query = ""
    var replacement = ""
    var options = FindOptions()
    var index = 0
    /// Wird hochgezählt, damit das Suchfeld den Cursor bekommt.
    var focusToken = 0
}

/// Leiste oben im Dokumentfenster (⌘ F): Suchen in Knoten und Notizen, Ersetzen.
struct FindBar: View {
    @Binding var state: FindState
    let matches: [FindMatch]
    let onNext: () -> Void
    let onPrevious: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Suchen", text: $state.query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
                    .focused($searchFocused)
                    .onSubmit(onNext)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 70, alignment: .leading)
                Button(action: onPrevious) { Image(systemName: "chevron.left") }
                    .help("Voriger Treffer (⇧ ⌘ G)")
                    .disabled(matches.isEmpty)
                Button(action: onNext) { Image(systemName: "chevron.right") }
                    .help("Nächster Treffer (⌘ G)")
                    .disabled(matches.isEmpty)
                Toggle("Notizen", isOn: $state.options.includeNotes)
                    .toggleStyle(.checkbox)
                    .help("Auch in den Notizen suchen")
                Toggle("Aa", isOn: $state.options.caseSensitive)
                    .toggleStyle(.checkbox)
                    .help("Groß- und Kleinschreibung beachten")
                Spacer(minLength: 0)
                Button("Fertig", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.2.squarepath").foregroundStyle(.secondary)
                TextField("Ersetzen durch", text: $state.replacement)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)
                Button("Ersetzen", action: onReplace)
                    .disabled(matches.isEmpty)
                Button("Alle ersetzen", action: onReplaceAll)
                    .disabled(matches.isEmpty)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { searchFocused = true }
        .onChange(of: state.focusToken) { _, _ in searchFocused = true }
    }

    private var status: String {
        if state.query.isEmpty { return "" }
        if matches.isEmpty { return L("keine Treffer") }
        return L("%@ von %@", "\(min(state.index, matches.count - 1) + 1)", "\(matches.count)")
    }
}
