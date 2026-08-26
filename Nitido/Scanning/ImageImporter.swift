import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum ImageImportError: Error, LocalizedError {
    case unreadable
    case unsupportedType
    case emptyPDF

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "import.error.unreadable",
                   defaultValue: "No se pudo leer el archivo.")
        case .unsupportedType:
            String(localized: "import.error.unsupportedType",
                   defaultValue: "Ese tipo de archivo no se puede importar.")
        case .emptyPDF:
            String(localized: "import.error.emptyPDF",
                   defaultValue: "El PDF no tiene páginas.")
        }
    }
}

/// Importación desde Fotos y desde Archivos. Servicio sin estado.
enum ImageImporter {

    /// Lado mayor al que se rasteriza un PDF. Por encima de esto no se gana
    /// legibilidad y sí se dispara la memoria.
    static let pdfMaxPixelSize: CGFloat = 3000

    // MARK: - Datos sueltos (Fotos)

    /// `PhotosPickerItem` es un tipo de SwiftUI, así que la extracción de datos
    /// se queda en la capa de vista y aquí solo entran `Data`. Ningún servicio
    /// importa SwiftUI.
    static func images(fromImageData items: [Data]) throws -> [SendableImage] {
        try items.map { data in
            guard let image = Downsampler.fullImage(from: data) else {
                throw ImageImportError.unreadable
            }
            return image
        }
    }

    // MARK: - Archivos

    /// Un fichero puede dar varias páginas: un PDF de doce páginas entra como
    /// un documento de doce páginas.
    static func images(fromFileAt url: URL) throws -> [SendableImage] {
        // Los ficheros que vienen del selector del sistema están fuera del
        // contenedor de la app y hay que pedir acceso explícitamente.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let type = UTType(filenameExtension: url.pathExtension)

        if type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf" {
            return try rasterize(pdf: data)
        }
        guard let image = Downsampler.fullImage(from: data) else {
            throw ImageImportError.unsupportedType
        }
        return [image]
    }

    // MARK: - PDF

    /// Rasteriza un PDF página a página con PDFKit.
    static func rasterize(pdf data: Data) throws -> [SendableImage] {
        guard let document = PDFDocument(data: data) else {
            throw ImageImportError.unreadable
        }
        guard document.pageCount > 0 else {
            throw ImageImportError.emptyPDF
        }

        var images: [SendableImage] = []
        images.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            // Página a página y dentro de un pool: un PDF grande rasterizado de
            // golpe se lleva la app por delante.
            try autoreleasepool {
                guard let page = document.page(at: index) else { return }
                guard let image = render(page) else {
                    throw ImageImportError.unreadable
                }
                images.append(SendableImage(image))
            }
        }

        guard !images.isEmpty else { throw ImageImportError.emptyPDF }
        return images
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        // `bounds(for:)` ya viene con la rotación de la página aplicada, y
        // `draw(with:to:)` la respeta, así que no hay que rotar a mano.
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(
            pdfMaxPixelSize / max(bounds.width, bounds.height),
            // Un PDF de texto a 72 ppp se lee fatal; 2x es el mínimo razonable.
            4
        )
        let pixelWidth = Int((bounds.width * scale).rounded())
        let pixelHeight = Int((bounds.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        // Un PDF puede tener fondo transparente; sobre blanco se ve como se ve
        // en cualquier visor.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // El contexto de Core Graphics y el espacio del PDF comparten origen
        // abajo a la izquierda, así que aquí no hay que voltear la Y.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
