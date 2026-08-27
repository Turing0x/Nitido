import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Caja para cruzar la frontera de actor con una `CGImage`.
///
/// `CGImage` es inmutable una vez creada: copiarla entre hilos es seguro y lo
/// único que hace el runtime es retener/soltar. Por eso el `@unchecked`, que
/// aquí es una afirmación consciente y no un parche para callar al compilador.
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation

    init(_ cgImage: CGImage, orientation: CGImagePropertyOrientation = .up) {
        self.cgImage = cgImage
        self.orientation = orientation
    }
}

enum ImageProcessorError: Error {
    case encodingFailed
}

/// Servicio sin estado de procesado de imagen. No importa SwiftUI ni conoce
/// ningún store.
enum ImageProcessor {

    /// Un único `CIContext` compartido para toda la app. Crear uno por
    /// operación es lento y se come la memoria; este se crea una sola vez.
    /// `CIContext` es `Sendable`, así que se puede usar desde cualquier hilo.
    static let ciContext: CIContext = {
        CIContext(options: [
            // Sin caché de fila intermedia: procesamos imágenes grandes de una
            // en una y no queremos que el contexto se quede con ellas.
            .cacheIntermediates: false,
            .useSoftwareRenderer: false
        ])
    }()

    /// Calidad JPEG del procesado que se guarda en disco.
    static let processedQuality: Double = 0.9
    /// Calidad JPEG de la miniatura.
    static let thumbnailQuality: Double = 0.8
    /// Lado mayor de la miniatura, en píxeles.
    static let thumbnailMaxPixelSize: CGFloat = 400

    // MARK: - Orientación

    /// Devuelve la imagen con la orientación ya aplicada (EXIF resuelto).
    ///
    /// Se hace aquí y una sola vez, al importar: a partir de ese momento todo
    /// el pipeline (recorte, OCR, PDF) trabaja con píxeles «rectos» y no hay
    /// que arrastrar la orientación por cada cálculo de coordenadas.
    static func normalized(_ image: SendableImage) -> CGImage {
        guard image.orientation != .up else { return image.cgImage }

        let oriented = CIImage(cgImage: image.cgImage).oriented(image.orientation)
        guard let rendered = ciContext.createCGImage(oriented, from: oriented.extent) else {
            // Si el render falla nos quedamos con los píxeles sin rotar antes
            // que perder la página.
            return image.cgImage
        }
        return rendered
    }

    // MARK: - Codificación

    /// Codifica el original. Se intenta HEIC por espacio y **se comprueba el
    /// resultado**: no todos los dispositivos ni todos los espacios de color
    /// aceptan HEIC. Si falla, se cae a JPEG de calidad alta.
    /// - Returns: los datos y la extensión que hay que usar en el nombre.
    static func encodeOriginal(_ image: CGImage) throws -> (data: Data, fileExtension: String) {
        if let heic = encode(image, as: UTType.heic, quality: 0.92) {
            return (heic, "heic")
        }
        guard let jpeg = encode(image, as: UTType.jpeg, quality: 0.95) else {
            throw ImageProcessorError.encodingFailed
        }
        return (jpeg, "jpg")
    }

    static func encodeProcessed(_ image: CGImage) throws -> Data {
        guard let data = encode(image, as: UTType.jpeg, quality: processedQuality) else {
            throw ImageProcessorError.encodingFailed
        }
        return data
    }

    static func encodeThumbnail(_ image: CGImage) throws -> Data {
        guard let data = encode(image, as: UTType.jpeg, quality: thumbnailQuality) else {
            throw ImageProcessorError.encodingFailed
        }
        return data
    }

    /// Igual que `encode`, pero con calidad configurable y visibilidad
    /// pública: lo usa `PDFCompression` para los tres niveles de exportación.
    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        encode(image, as: UTType.jpeg, quality: quality)
    }

    /// Codifica sin pérdida, para exportar páginas sueltas a PNG.
    static func encodePNG(_ image: CGImage) -> Data? {
        encode(image, as: UTType.png, quality: 1)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            type.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
