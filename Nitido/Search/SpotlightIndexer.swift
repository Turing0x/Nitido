import CoreSpotlight
import Foundation

/// Identificador único de un documento en el índice de Spotlight, y su
/// conversión de vuelta a `UUID` para el deep link.
enum SpotlightItemID {
    private static let prefix = "nitido.document."

    static func identifier(for documentID: UUID) -> String {
        prefix + documentID.uuidString.lowercased()
    }

    static func documentID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }
}

/// Lo mínimo que hace falta para indexar un documento. `Sendable` y sin
/// modelos de SwiftData, igual que `PageAssetInfo`/`PageRecord`.
struct DocumentSearchSummary: Sendable, Equatable {
    let documentID: UUID
    let title: String
    let searchText: String
    let createdAt: Date
    let updatedAt: Date
}

/// Servicio sin estado sobre `CSSearchableIndex`. No requiere entitlements ni
/// declaraciones adicionales en `Info.plist`.
struct SpotlightIndexer: Sendable {
    static let domainIdentifier = "com.threedotsdev.nitido.documents"

    func index(_ summary: DocumentSearchSummary) async {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = summary.title
        attributes.contentDescription = String(summary.searchText.prefix(200))
        attributes.keywords = Self.keywords(from: summary.searchText)
        attributes.contentCreationDate = summary.createdAt
        attributes.contentModificationDate = summary.updatedAt

        let item = CSSearchableItem(
            uniqueIdentifier: SpotlightItemID.identifier(for: summary.documentID),
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )
        try? await CSSearchableIndex.default().indexSearchableItems([item])
    }

    func deindex(_ documentIDs: [UUID]) async {
        guard !documentIDs.isEmpty else { return }
        let identifiers = documentIDs.map { SpotlightItemID.identifier(for: $0) }
        try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: identifiers)
    }

    private static func keywords(from text: String, maxCount: Int = 20) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where word.count > 3 {
            let lower = word.lowercased()
            if seen.insert(lower).inserted {
                result.append(lower)
                if result.count == maxCount { break }
            }
        }
        return result
    }
}
