import CoreGraphics
import Foundation
import Vision

/// Reconoce el texto de una página con el Vision moderno de Swift.
///
/// Servicio sin estado, igual forma que `PageIngestor`/`DocumentQuadDetector`:
/// no conoce SwiftData ni `FileStoring`, solo recibe píxeles y devuelve un
/// resultado `Sendable`.
struct TextRecognizer: Sendable {
    /// Español e inglés como candidatos prioritarios; sirven de refuerzo
    /// aunque la detección automática de idioma acierte por su cuenta.
    static let candidateLanguages: [Locale.Language] = [
        Locale.Language(identifier: "es"),
        Locale.Language(identifier: "en")
    ]

    /// Reconoce el texto de una página ya procesada (filtrada/recortada): el
    /// contraste del modo Documento mejora bastante la tasa de acierto frente
    /// al original sin tocar.
    ///
    /// Las cajas quedan en el espacio normalizado nativo de Vision, con
    /// origen abajo a la izquierda, sin conversión de eje Y — eso se hace en
    /// el punto de dibujo del exportador de PDF (Sprint 4).
    func recognize(_ image: CGImage) async throws -> (text: String, boxes: [OCRBox]) {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = Self.candidateLanguages

        let handler = ImageRequestHandler(image)
        let observations = try await handler.perform(request)

        let boxes: [OCRBox] = observations.compactMap { observation -> OCRBox? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // `RecognizedTextObservation` no expone un `boundingBox` directo:
            // da las cuatro esquinas del cuadrilátero (puede venir ligeramente
            // rotado). Se calcula el rectángulo que las envuelve.
            let xs = [observation.topLeft.x, observation.topRight.x, observation.bottomRight.x, observation.bottomLeft.x]
            let ys = [observation.topLeft.y, observation.topRight.y, observation.bottomRight.y, observation.bottomLeft.y]
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max()
            else { return nil }
            return OCRBox(
                text: candidate.string,
                x: Double(minX),
                y: Double(minY),
                width: Double(maxX - minX),
                height: Double(maxY - minY),
                confidence: Double(candidate.confidence)
            )
        }

        let ordered = boxes.inReadingOrder()
        let text = ordered.map(\.text).joined(separator: "\n")
        return (text, ordered)
    }
}
