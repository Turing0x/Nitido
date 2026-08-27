import Foundation

/// Búsqueda sobre título y texto reconocido, compartida por `LibraryView` (filtro
/// rápido) y `SearchView` (búsqueda explícita con fragmento resaltado).
///
/// Servicio puro: sin SwiftData, sin CoreSpotlight, sin estado.
enum DocumentSearch {
    struct Result: Identifiable, Sendable, Equatable {
        let documentID: UUID
        let title: String
        /// Fragmento del OCR con contexto alrededor de la coincidencia, o
        /// `nil` si solo coincide el título.
        let snippet: String?
        var id: UUID { documentID }
    }

    static func results(for query: String, in documents: [ScanDocument], snippetContext: Int = 60) -> [Result] {
        guard !query.isEmpty else { return [] }
        return documents.compactMap { document in
            let titleMatches = document.title.localizedStandardContains(query)
            let matchSnippet = snippet(in: document.searchText, matching: query, contextChars: snippetContext)
            guard titleMatches || matchSnippet != nil else { return nil }
            return Result(documentID: document.id, title: document.title, snippet: matchSnippet)
        }
    }

    /// Recorta el texto reconocido alrededor de la primera coincidencia, para
    /// no volcar el documento entero en la fila de resultados.
    static func snippet(in text: String, matching query: String, contextChars: Int) -> String? {
        guard !query.isEmpty,
              let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
        else { return nil }

        let start = text.index(range.lowerBound, offsetBy: -contextChars, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: contextChars, limitedBy: text.endIndex) ?? text.endIndex
        var fragment = String(text[start..<end])
        if start != text.startIndex { fragment = "…" + fragment }
        if end != text.endIndex { fragment += "…" }
        return fragment
    }
}
