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
                try ingestOne(image, documentID: documentID, index: startingIndex + offset)
            }
            records.append(record)
            onProgress?(offset + 1, images.count)
        }

        return records
    }

    private func ingestOne(
        _ image: SendableImage,
        documentID: UUID,
        index: Int
    ) throws -> PageRecord {
        let pageID = UUID()
        let normalized = ImageProcessor.normalized(image)

        // 1. Original tal cual, en HEIC si el dispositivo lo acepta.
        let original = try ImageProcessor.encodeOriginal(normalized)
        let originalName = fileStore.fileName(
            for: .original, pageID: pageID, fileExtension: original.fileExtension
        )
        try fileStore.write(original.data, fileName: originalName, documentID: documentID)

        // 2. Procesado. En la Sprint 1 es el original recodificado a JPEG: la
        //    corrección de perspectiva y el recorte ya vienen hechos de
        //    VisionKit. Los filtros entran aquí en la Sprint 2, siempre de
        //    forma no destructiva sobre el original, que no se toca nunca.
        let processedData = try ImageProcessor.encodeProcessed(normalized)
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
            thumbnailFileName: thumbnailName
        )
    }
}
