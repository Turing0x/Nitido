import SwiftUI

/// Rejilla adaptable de las pantallas de documentos y páginas.
///
/// Los tokens no traen un ancho de celda, así que se compone con los de
/// espaciado (2 × x20 = 160 pt): en un iPhone vertical (362 pt útiles) siguen
/// saliendo dos columnas, como hasta ahora, y en iPad cada columna que cabe se
/// aprovecha. No es un valor de diseño nuevo, es la anchura mínima con la que
/// las celdas ya se veían bien.
extension DS {
    enum Layout {
        static let gridCellMinimum: CGFloat = DS.Spacing.x20 * 2

        static let adaptiveGridColumns: [GridItem] = [
            GridItem(.adaptive(minimum: gridCellMinimum), spacing: DS.Spacing.x4)
        ]
    }
}
