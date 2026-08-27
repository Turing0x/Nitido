import Foundation

/// Resultado del OCR de una página, listo para persistir.
///
/// `Sendable` y plano a propósito: es lo único que cruza de la tarea de
/// reconocimiento al actor de SwiftData. Nunca se pasan modelos entre actores.
struct PageOCRResult: Sendable, Equatable {
    let pageID: UUID
    let text: String
    let boxes: [OCRBox]
}
