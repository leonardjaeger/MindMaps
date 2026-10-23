import Foundation

// MARK: - Links zwischen Dokumenten (M7)

/// Links auf einen Knoten in einem MindMaps-Dokument:
/// `mindmaps://open?file=/Pfad/zum/Dokument.mindmaps&node=UUID`
enum DocumentLink {
    static let scheme = "mindmaps"

    static func make(file: URL, node: UUID?) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "open"
        var items = [URLQueryItem(name: "file", value: file.standardizedFileURL.path)]
        if let node { items.append(URLQueryItem(name: "node", value: node.uuidString)) }
        components.queryItems = items
        return components.string ?? ""
    }

    /// Datei und Knoten aus einem Link – `nil`, wenn es kein MindMaps-Link ist.
    /// Anlegen-Links (`mindmaps://add?…`, 1.3) sind keine Öffnen-Links, auch wenn sie `file=` haben.
    static func parse(_ link: String) -> (file: URL, node: UUID?)? {
        guard let components = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() != ExternalNodeRequest.host,
              let path = components.queryItems?.first(where: { $0.name == "file" })?.value,
              !path.isEmpty else { return nil }
        let node = components.queryItems?.first(where: { $0.name == "node" })?.value.flatMap(UUID.init(uuidString:))
        return (URL(fileURLWithPath: path), node)
    }

    static func isDocumentLink(_ link: String) -> Bool { parse(link) != nil }

    /// Web-Adresse ohne Schema bekommt `https://`.
    static func normalized(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.hasPrefix("mailto:") else { return trimmed }
        return "https://" + trimmed
    }
}

// MARK: - Fokus, Verbindungen, Bilder

extension Node {
    /// IDs des Teilbaums (inklusive dieses Knotens).
    var subtreeIDs: Set<UUID> { ids { _ in true } }

    /// Fokusmodus: alles außer dem Weg zum Knoten und seinem Teilbaum wird blass.
    func idsOutsideFocus(of id: UUID) -> Set<UUID> {
        guard let path = path(to: id), let focus = node(withID: id) else { return [] }
        return subtreeIDs.subtracting(path).subtracting(focus.subtreeIDs)
    }

    /// Alle Bilddateien, auf die der Baum verweist.
    var referencedAssets: Set<String> {
        var result = Set<String>()
        func visit(_ node: Node) {
            if let image = node.image { result.insert(image.asset) }
            node.children.forEach(visit)
        }
        visit(self)
        return result
    }
}

extension MindMapDocumentData {
    /// Entfernt Verbindungen, deren Knoten es nicht mehr gibt, und Verbindungen eines Knotens zu sich selbst.
    mutating func pruneConnections() {
        let existing = root.subtreeIDs
        connections.removeAll { !existing.contains($0.from) || !existing.contains($0.to) || $0.from == $0.to }
    }

    /// Gibt es schon eine Verbindung zwischen den beiden Knoten (in dieser Richtung)?
    func hasConnection(from: UUID, to: UUID) -> Bool {
        connections.contains { $0.from == from && $0.to == to }
    }
}

// MARK: - Präsentation (M7)

/// Reihenfolge der Präsentation: erst der Hauptknoten, dann Zweig für Zweig.
///
/// Jeder Schritt deckt einen weiteren Knoten der ersten beiden Ebenen auf (in Lesereihenfolge);
/// tiefere Knoten erscheinen zusammen mit ihrem Knoten der zweiten Ebene. Am Ende: Übersicht.
struct PresentationPlan: Equatable {
    struct Step: Equatable {
        /// Knoten, um den es in diesem Schritt geht (bei der Übersicht der Hauptknoten).
        let focus: UUID
        /// Alles, was ab diesem Schritt sichtbar ist.
        let revealed: Set<UUID>
        /// Knoten, auf die die Kamera zielt (aktueller Hauptast bzw. alles).
        let camera: Set<UUID>
        let isOverview: Bool
    }

    let steps: [Step]

    init(root: Node) {
        var steps: [Step] = []
        var revealed: Set<UUID> = [root.id]
        steps.append(Step(focus: root.id, revealed: revealed, camera: [root.id], isOverview: false))

        if !root.isCollapsed {
            for branch in root.children {
                revealed.insert(branch.id)
                var branchVisible: Set<UUID> = [branch.id]
                steps.append(Step(focus: branch.id, revealed: revealed,
                                  camera: branchVisible.union([root.id]), isOverview: false))
                guard !branch.isCollapsed else { continue }
                for child in branch.children {
                    let subtree = child.subtreeIDs
                    revealed.formUnion(subtree)
                    branchVisible.formUnion(subtree)
                    steps.append(Step(focus: child.id, revealed: revealed,
                                      camera: branchVisible.union([root.id]), isOverview: false))
                }
            }
        }
        if steps.count > 1 {
            let all = root.subtreeIDs
            steps.append(Step(focus: root.id, revealed: all, camera: all, isOverview: true))
        }
        self.steps = steps
    }
}
