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

/// Fuente de páginas que se materializan **por lotes**, no todas de golpe.
///
/// Importar un PDF de cuarenta páginas decodificándolas a la vez son varios
/// gigabytes: con `pdfMaxPixelSize` a 3000, una página A4 rasterizada ronda los
/// 50 MB sin comprimir, y el sistema mata la app mucho antes de llegar al
/// final. Los `autoreleasepool` no ayudaban porque el array las retenía todas.
///
/// Con esto solo viven las páginas del lote en curso: se escriben en disco y se
/// sueltan antes de pedir el siguiente.
struct PageBatchProvider: Sendable {
    /// Cuántas páginas caben en memoria a la vez. Tres es el equilibrio entre
    /// aprovechar la detección en paralelo y no acercarse al techo de memoria:
    /// cada página en vuelo son el original decodificado **y** su versión
    /// normalizada, así que el pico real es el doble de lo que parece.
    static let batchSize = 3

    let count: Int
    /// Si las páginas de esta fuente deben pasar por la detección de bordes.
    /// Un PDF ya viene encuadrado y una captura de VisionKit ya viene
    /// recortada; detectar ahí solo puede empeorar el resultado.
    let detectsDocument: Bool
    /// Materializa las páginas de `range`. Se llama una vez por lote, desde
    /// una tarea de fondo.
    let batch: @Sendable (Range<Int>) throws -> [SendableImage]

    /// Rangos en que se recorre la fuente, de `batchSize` en `batchSize`.
    var batchRanges: [Range<Int>] {
        stride(from: 0, to: count, by: Self.batchSize).map { lowerBound in
            lowerBound..<Swift.min(lowerBound + Self.batchSize, count)
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

    // MARK: - Proveedores por lotes

    /// Páginas ya decodificadas (captura de la cámara): no hay nada que
    /// materializar, pero se envuelven igual para que el pipeline de ingesta
    /// tenga un único camino.
    static func provider(for images: [SendableImage], detectsDocument: Bool) -> PageBatchProvider {
        PageBatchProvider(count: images.count, detectsDocument: detectsDocument) { range in
            Array(images[range])
        }
    }

    /// Fotos: se conservan los datos **comprimidos** y se decodifica por lotes.
    /// Un HEIC de 2 MB son ~50 MB una vez decodificado, así que guardar la
    /// forma comprimida y decodificar bajo demanda es la diferencia entre
    /// importar treinta fotos y que el sistema mate la app.
    static func provider(forImageData items: [Data]) -> PageBatchProvider {
        PageBatchProvider(count: items.count, detectsDocument: true) { range in
            try images(fromImageData: Array(items[range]))
        }
    }

    /// Un fichero puede dar varias páginas: un PDF de doce páginas entra como
    /// un documento de doce páginas, rasterizadas por lotes.
    static func provider(forFileAt url: URL) throws -> PageBatchProvider {
        // Los ficheros que vienen del selector del sistema están fuera del
        // contenedor de la app y hay que pedir acceso explícitamente.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        // Se lee entero aquí, mientras dura el permiso de acceso. No se mapea
        // (`.mappedIfSafe`) porque el proveedor rasteriza después, ya fuera del
        // ámbito de seguridad, y unos datos mapeados dejarían de ser legibles.
        // Es la forma comprimida del fichero: muy por debajo de lo que ocupan
        // sus páginas decodificadas, que es lo que de verdad había que evitar.
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension)
        let isPDF = type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf"

        guard isPDF else {
            guard let image = Downsampler.fullImage(from: data) else {
                throw ImageImportError.unsupportedType
            }
            return PageBatchProvider(count: 1, detectsDocument: true) { _ in [image] }
        }

        let pageCount = try pdfPageCount(of: data)
        return PageBatchProvider(count: pageCount, detectsDocument: false) { range in
            try rasterize(pdf: data, pages: range)
        }
    }

    /// Número de páginas de un PDF, sin rasterizar ninguna.
    static func pdfPageCount(of data: Data) throws -> Int {
        guard let document = PDFDocument(data: data) else {
            throw ImageImportError.unreadable
        }
        guard document.pageCount > 0 else {
            throw ImageImportError.emptyPDF
        }
        return document.pageCount
    }

    // MARK: - PDF

    /// Rasteriza un PDF página a página con PDFKit.
    ///
    /// - Parameter range: páginas a rasterizar. `nil` las hace todas, que es lo
    ///   que necesitan los tests pero **no** el camino de producción: ahí se
    ///   pide siempre un lote acotado (ver `provider(forFileAt:)`), porque
    ///   materializar un PDF entero se lleva la app por delante.
    static func rasterize(pdf data: Data, pages range: Range<Int>? = nil) throws -> [SendableImage] {
        guard let document = PDFDocument(data: data) else {
            throw ImageImportError.unreadable
        }
        guard document.pageCount > 0 else {
            throw ImageImportError.emptyPDF
        }

        let indices = (range ?? 0..<document.pageCount).clamped(to: 0..<document.pageCount)
        var images: [SendableImage] = []
        images.reserveCapacity(indices.count)

        for index in indices {
            // Página a página y dentro de un pool, para que el pico sea el de
            // una página y no el del lote entero.
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
