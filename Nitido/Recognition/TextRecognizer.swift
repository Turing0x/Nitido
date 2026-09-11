import CoreGraphics
import Foundation
import Vision

/// Reconoce el texto de una página con el Vision moderno de Swift.
///
/// Servicio sin estado, igual forma que `PageIngestor`/`DocumentQuadDetector`:
/// no conoce SwiftData ni `FileStoring`, solo recibe píxeles y devuelve un
/// resultado `Sendable`.
/// Preferencia de idioma de OCR, elegible en Ajustes. `automatic` es el
/// comportamiento histórico (español e inglés como candidatos, detección
/// automática); un idioma concreto lo fuerza, para documentos en un idioma
/// distinto que la detección automática podría confundir con español/inglés.
enum OCRLanguagePreference: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case spanish
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: String(localized: "settings.ocrLanguage.automatic", defaultValue: "Automático")
        case .spanish: String(localized: "settings.ocrLanguage.spanish", defaultValue: "Español")
        case .english: String(localized: "settings.ocrLanguage.english", defaultValue: "Inglés")
        }
    }

    /// (candidatos, si se deja que Vision detecte por su cuenta).
    var recognitionParameters: (languages: [Locale.Language], automatic: Bool) {
        switch self {
        case .automatic: (TextRecognizer.candidateLanguages, true)
        case .spanish: ([Locale.Language(identifier: "es")], false)
        case .english: ([Locale.Language(identifier: "en")], false)
        }
    }
}

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
    ///
    /// - Parameters:
    ///   - languages: candidatos de idioma. Por defecto español e inglés.
    ///   - automaticallyDetectsLanguage: si es `false`, fuerza `languages` en
    ///     vez de dejar que Vision decida — Ajustes ofrece elegir el idioma a
    ///     mano para documentos en un idioma poco frecuente.
    func recognize(
        _ image: CGImage,
        languages: [Locale.Language] = TextRecognizer.candidateLanguages,
        automaticallyDetectsLanguage: Bool = true
    ) async throws -> (text: String, boxes: [OCRBox]) {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
        request.recognitionLanguages = languages

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
