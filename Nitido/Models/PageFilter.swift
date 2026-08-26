import Foundation

/// Filtros de procesado disponibles para una página.
/// El valor bruto (`rawValue`) es lo que se persiste en `ScanPage.filterRaw`;
/// no se debe renombrar sin una migración.
enum PageFilter: String, CaseIterable, Codable, Sendable, Identifiable {
    case original
    case enhancedColor
    case grayscale
    case document
    case blackAndWhite

    var id: String { rawValue }

    /// Filtro sugerido por defecto para páginas mayoritariamente de texto.
    static let recommendedDefault: PageFilter = .document

    var displayName: String {
        switch self {
        case .original: String(localized: "filter.original", defaultValue: "Original")
        case .enhancedColor: String(localized: "filter.enhancedColor", defaultValue: "Color mejorado")
        case .grayscale: String(localized: "filter.grayscale", defaultValue: "Escala de grises")
        case .document: String(localized: "filter.document", defaultValue: "Documento")
        case .blackAndWhite: String(localized: "filter.blackAndWhite", defaultValue: "Blanco y negro")
        }
    }
}
