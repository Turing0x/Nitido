import Foundation
import SwiftData

@Model
final class ScanDocument {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFavorite: Bool = false
    /// Borrado lógico: si no es nil, el documento está en la papelera.
    var deletedAt: Date?
    var folder: ScanFolder?
    /// Concatenación del OCR de todas las páginas. Es el campo sobre el que
    /// buscan los predicados de SwiftData; se recalcula al terminar el OCR.
    var searchText: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ScanPage.document)
    var pages: [ScanPage] = []

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isFavorite: Bool = false,
        deletedAt: Date? = nil,
        folder: ScanFolder? = nil,
        searchText: String = "",
        pages: [ScanPage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.deletedAt = deletedAt
        self.folder = folder
        self.searchText = searchText
        self.pages = pages
    }

    /// Páginas en su orden de presentación.
    var orderedPages: [ScanPage] {
        pages.sorted { $0.index < $1.index }
    }

    /// Título por defecto de una captura nueva: "Escaneo" + fecha corta localizada.
    static func defaultTitle(for date: Date = .now) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return String(
            localized: "document.defaultTitle",
            defaultValue: "Escaneo \(formatted)"
        )
    }
}
