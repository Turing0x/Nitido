import CoreGraphics
import Foundation

/// Descriptor de una página ya escrita en disco.
///
/// Es un tipo `Sendable` y plano a propósito: es lo único que cruza de la tarea
/// de procesado al actor de SwiftData. Nunca se pasan modelos entre actores.
struct PageRecord: Sendable, Equatable {
    let pageID: UUID
    let index: Int
    let originalFileName: String
    let processedFileName: String
    let thumbnailFileName: String
    let filter: PageFilter
    let documentEnhancementIntensity: Double
    let quad: QuadPoints?

    init(
        pageID: UUID,
        index: Int,
        originalFileName: String,
        processedFileName: String,
        thumbnailFileName: String,
        filter: PageFilter = .original,
        documentEnhancementIntensity: Double = 1,
        quad: QuadPoints? = nil
    ) {
        self.pageID = pageID
        self.index = index
        self.originalFileName = originalFileName
        self.processedFileName = processedFileName
        self.thumbnailFileName = thumbnailFileName
        self.filter = filter
        self.documentEnhancementIntensity = documentEnhancementIntensity
        self.quad = quad
    }
}

/// Escribe en disco las tres variantes de cada página.
///
/// Servicio sin estado: solo depende de `FileStoring`. No conoce SwiftData ni
/// SwiftUI, y se ejecuta fuera del hilo principal.
struct PageIngestor: Sendable {
    let fileStore: any FileStoring

    /// - Parameters:
    ///   - images: páginas en el orden en que se capturaron o importaron.
    ///   - startingIndex: primer índice libre del documento, para poder añadir
    ///     páginas a un documento que ya existe.
    ///   - onProgress: (hechas, total). Se llama desde la tarea de fondo.
    func ingest(
        _ images: [SendableImage],
        documentID: UUID,
        startingIndex: Int = 0,
        detectedQuads: [QuadPoints?] = [],
        normalizedImages: [CGImage?] = [],
        defaultFilter: PageFilter = .original,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) throws -> [PageRecord] {
        try fileStore.createDocumentDirectory(for: documentID)

        var records: [PageRecord] = []
        records.reserveCapacity(images.count)

        for (offset, image) in images.enumerated() {
            // Una página cada vez y dentro de su propio pool: una captura de un
            // iPhone reciente son varios megapíxeles y, sin esto, procesar una
            // tanda de diez páginas mantiene las diez vivas hasta el final.
            let record = try autoreleasepool {
                try ingestOne(
                    image,
                    documentID: documentID,
                    index: startingIndex + offset,
                    detectedQuad: detectedQuads[safe: offset] ?? nil,
                    normalized: normalizedImages[safe: offset] ?? nil,
                    defaultFilter: defaultFilter
                )
            }
            records.append(record)
            onProgress?(offset + 1, images.count)
        }

        return records
    }

    private func ingestOne(
        _ image: SendableImage,
        documentID: UUID,
        index: Int,
        detectedQuad: QuadPoints?,
        normalized precomputedNormalized: CGImage? = nil,
        defaultFilter: PageFilter = .original
    ) throws -> PageRecord {
        let pageID = UUID()
        let normalized = precomputedNormalized ?? ImageProcessor.normalized(image)

        // 1. Original tal cual, en HEIC si el dispositivo lo acepta.
        let original = try ImageProcessor.encodeOriginal(normalized)
        let originalName = fileStore.fileName(
            for: .original, pageID: pageID, fileExtension: original.fileExtension
        )
        try fileStore.write(original.data, fileName: originalName, documentID: documentID)

        // 2. Procesado derivado del original. VisionKit ya entrega la captura
        //    recortada; Fotos y Archivos llegan con un cuadrilátero detectado
        //    y el filtro Documento, siempre sin tocar el fichero original.
        let usableQuad = detectedQuad.flatMap { $0.isValidForEditing ? $0 : nil }
        var configuration = PageEditConfiguration(
            filter: usableQuad == nil ? defaultFilter : .document,
            documentEnhancementIntensity: 1,
            quad: usableQuad ?? .full
        )
        let processedImage: CGImage
        if configuration.filter == .original, configuration.quad.isFullImage {
            processedImage = normalized
        } else if let rendered = try? PageRenderer.fullResolution(normalized, configuration: configuration) {
            processedImage = rendered
        } else {
            // El recorte/filtro detectado no se pudo renderizar (p.ej. cuadrilátero
            // degenerado): no por eso se descarta la página entera, se importa sin
            // recortar como antes de tener detección.
            configuration = PageEditConfiguration(filter: .original, documentEnhancementIntensity: 1, quad: .full)
            processedImage = normalized
        }
        let processedData = try ImageProcessor.encodeProcessed(processedImage)
        let processedName = fileStore.fileName(
            for: .processed, pageID: pageID, fileExtension: "jpg"
        )
        try fileStore.write(processedData, fileName: processedName, documentID: documentID)

        // 3. Miniatura, desde el procesado y sin decodificarlo entero.
        let thumbnailName = fileStore.fileName(
            for: .thumbnail, pageID: pageID, fileExtension: "jpg"
        )
        if let thumbnail = Downsampler.thumbnail(
            from: processedData,
            maxPixelSize: ImageProcessor.thumbnailMaxPixelSize
        ) {
            let thumbnailData = try ImageProcessor.encodeThumbnail(thumbnail)
            try fileStore.write(thumbnailData, fileName: thumbnailName, documentID: documentID)
        }
        // Si la miniatura no sale, no es motivo para tirar la página: el nombre
        // queda guardado y se regenera al pintarla.

        return PageRecord(
            pageID: pageID,
            index: index,
            originalFileName: originalName,
            processedFileName: processedName,
            thumbnailFileName: thumbnailName,
            filter: configuration.filter,
            documentEnhancementIntensity: configuration.documentEnhancementIntensity,
            quad: configuration.filter == .original ? nil : usableQuad
        )
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
