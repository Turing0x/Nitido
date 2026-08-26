import Foundation

/// Lee la miniatura de una página y, si no está, la regenera desde el
/// procesado. Servicio sin estado; se ejecuta fuera del hilo principal.
struct ThumbnailLoader: Sendable {
    let fileStore: any FileStoring

    /// - Returns: los datos JPEG de la miniatura, o `nil` si la página ya no
    ///   tiene ni miniatura ni procesado en disco.
    func loadData(
        documentID: UUID,
        thumbnailFileName: String,
        processedFileName: String
    ) -> Data? {
        if let data = try? fileStore.read(fileName: thumbnailFileName, documentID: documentID) {
            return data
        }

        // Las miniaturas se pueden perder: están fuera de la copia de seguridad
        // y se pueden borrar para liberar espacio. Antes de dejar un hueco en la
        // celda, se regenera desde el procesado.
        return autoreleasepool { () -> Data? in
            guard let processed = try? fileStore.read(
                fileName: processedFileName, documentID: documentID
            ) else { return nil }

            guard let thumbnail = Downsampler.thumbnail(
                from: processed,
                maxPixelSize: ImageProcessor.thumbnailMaxPixelSize
            ), let data = try? ImageProcessor.encodeThumbnail(thumbnail) else { return nil }

            _ = try? fileStore.write(data, fileName: thumbnailFileName, documentID: documentID)
            return data
        }
    }
}
