import CoreGraphics
import Foundation

/// Tres niveles de compresión para las imágenes que se incrustan en el PDF o
/// se exportan sueltas. Lado mayor en píxeles y calidad JPEG, tal como pide
/// el HANDOFF: es la información que la gente busca cuando tiene que subir un
/// documento a una sede electrónica con límite de tamaño.
enum PDFCompressionLevel: String, CaseIterable, Sendable, Codable {
    case high, medium, low

    var maxDimension: CGFloat {
        switch self {
        case .high: 3_000
        case .medium: 2_000
        case .low: 1_400
        }
    }

    var jpegQuality: Double {
        switch self {
        case .high: 0.85
        case .medium: 0.6
        case .low: 0.4
        }
    }
}

enum PDFCompressionError: Error {
    case unreadableImage
    case encodingFailed
}

enum PDFCompression {
    /// Reescala (si hace falta) y devuelve la imagen decodificada al tamaño
    /// del nivel pedido. Usa `Downsampler.thumbnail`, que decodifica
    /// directamente al tamaño final sin materializar la imagen completa en
    /// memoria — el mismo motivo por el que ya se usa para las miniaturas.
    static func compressedImage(from sourceData: Data, level: PDFCompressionLevel) throws -> CGImage {
        guard let image = Downsampler.thumbnail(from: sourceData, maxPixelSize: level.maxDimension) else {
            throw PDFCompressionError.unreadableImage
        }
        return image
    }

    /// Bytes JPEG reales al nivel dado: es lo que se dibuja en el PDF y
    /// también la unidad de la estimación de peso, así que no pueden
    /// desincronizarse entre sí.
    static func compressedJPEGData(from sourceData: Data, level: PDFCompressionLevel) throws -> Data {
        let image = try compressedImage(from: sourceData, level: level)
        guard let data = ImageProcessor.encodeJPEG(image, quality: level.jpegQuality) else {
            throw PDFCompressionError.encodingFailed
        }
        return data
    }
}

/// Peso aproximado del PDF final para un nivel de compresión, antes de
/// generarlo. Suma los bytes JPEG reales de cada página (los mismos que
/// dibuja `PDFExporter`) más un margen fijo de estructura por página
/// (fuentes del texto invisible, objetos del PDF). El margen es una
/// estimación conservadora, no medida contra `UIGraphicsPDFRenderer`
/// real —a afinar si en pruebas con documentos reales se aleja demasiado.
enum PDFSizeEstimator {
    private static let perPageOverheadBytes: Int64 = 3_000

    static func estimatedFileSize(
        for info: DocumentExportInfo,
        level: PDFCompressionLevel,
        fileStore: any FileStoring,
        documentID: UUID
    ) throws -> Int64 {
        var total = Int64(info.pages.count) * perPageOverheadBytes
        for page in info.pages {
            let data = try fileStore.read(fileName: page.processedFileName, documentID: documentID)
            let compressed = try PDFCompression.compressedJPEGData(from: data, level: level)
            total += Int64(compressed.count)
        }
        return total
    }
}
