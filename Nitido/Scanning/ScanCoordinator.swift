import AVFoundation
import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Orquesta la captura y la importación: coge las imágenes, las manda a
/// procesar fuera del hilo principal y crea el documento.
///
/// Vive en el actor principal porque es estado de interfaz. El trabajo pesado
/// sale de aquí en tareas separadas y solo vuelven tipos `Sendable`.
@MainActor
@Observable
final class ScanCoordinator {

    enum Phase: Equatable {
        case idle
        case working(done: Int, total: Int)

        var isWorking: Bool { self != .idle }
    }

    private(set) var phase: Phase = .idle
    /// Documento recién creado, para que la biblioteca navegue a él.
    var createdDocumentID: UUID?
    var errorMessage: String?

    private let documentStore: DocumentStore
    private let fileStore: any FileStoring

    init(modelContainer: ModelContainer, fileStore: any FileStoring) {
        self.documentStore = DocumentStore(modelContainer: modelContainer)
        self.fileStore = fileStore
    }

    // MARK: - Captura e importación

    func createDocument(from images: [SendableImage], detectDocuments: Bool = false) async {
        await createDocument(from: images, detectionMask: Array(repeating: detectDocuments, count: images.count))
    }

    func createDocument(from images: [SendableImage], detectionMask: [Bool]) async {
        guard !images.isEmpty else { return }
        let documentID = UUID()
        let title = ScanDocument.defaultTitle()

        do {
            let records = try await ingest(
                images,
                documentID: documentID,
                startingIndex: 0,
                detectionMask: detectionMask
            )
            try await documentStore.createDocument(id: documentID, title: title, records: records)
            createdDocumentID = documentID
        } catch {
            // Si algo falla a mitad, el directorio a medio escribir no se queda
            // ocupando sitio ni ensuciando el cálculo de espacio.
            try? fileStore.deleteDocumentDirectory(for: documentID)
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }

    func addPages(_ images: [SendableImage], to documentID: UUID, detectDocuments: Bool = false) async {
        await addPages(images, to: documentID, detectionMask: Array(repeating: detectDocuments, count: images.count))
    }

    func addPages(_ images: [SendableImage], to documentID: UUID, detectionMask: [Bool]) async {
        guard !images.isEmpty else { return }
        do {
            let startingIndex = try await documentStore.nextPageIndex(for: documentID)
            let records = try await ingest(
                images,
                documentID: documentID,
                startingIndex: startingIndex,
                detectionMask: detectionMask
            )
            try await documentStore.appendPages(records, to: documentID)
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
    }

    func importFromPhotos(_ items: [PhotosPickerItem], into documentID: UUID? = nil) async {
        guard !items.isEmpty else { return }
        phase = .working(done: 0, total: items.count)
        do {
            var payloads: [Data] = []
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageImportError.unreadable
                }
                payloads.append(data)
            }
            // La decodificación sale del hilo principal.
            let images = try await Task.detached(priority: .userInitiated) {
                try ImageImporter.images(fromImageData: payloads)
            }.value

            if let documentID {
                await addPages(images, to: documentID, detectDocuments: true)
            } else {
                await createDocument(from: images, detectDocuments: true)
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    func importFromFiles(result: Result<[URL], Error>, into documentID: UUID? = nil) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            phase = .working(done: 0, total: urls.count)
            do {
                // Leer y rasterizar (un PDF puede traer decenas de páginas) fuera
                // del hilo principal.
                let imported = try await Task.detached(priority: .userInitiated) {
                    try urls.map { url -> (images: [SendableImage], detect: Bool) in
                        let images = try ImageImporter.images(fromFileAt: url)
                        let type = UTType(filenameExtension: url.pathExtension)
                        let isPDF = type?.conforms(to: .pdf) == true || url.pathExtension.lowercased() == "pdf"
                        return (images, !isPDF)
                    }
                }.value
                let images = imported.flatMap(\.images)
                let detectionMask = imported.flatMap { pair in
                    Array(repeating: pair.detect, count: pair.images.count)
                }

                if let documentID {
                    await addPages(images, to: documentID, detectionMask: detectionMask)
                } else {
                    await createDocument(from: images, detectionMask: detectionMask)
                }
            } catch {
                errorMessage = error.localizedDescription
                phase = .idle
            }
        }
    }

    /// Traduce el fallo que devuelve VisionKit.
    ///
    /// Cuando el usuario deniega la cámara, `didFailWithError` llega con un
    /// `AVFoundationErrorDomain -11852` cuyo `localizedDescription` no le dice
    /// nada a nadie. Se comprueba el permiso —más fiable que el código— y se
    /// explica qué hacer y qué alternativas quedan.
    func reportCameraError(_ error: Error) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            errorMessage = String(
                localized: "scan.error.cameraDenied",
                defaultValue: "Nítido no tiene permiso para usar la cámara. Puedes activarlo en Ajustes › Nítido › Cámara. Mientras tanto, puedes importar documentos desde Fotos o desde Archivos."
            )
        case .notDetermined, .authorized:
            errorMessage = error.localizedDescription
        @unknown default:
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Gestión de documentos

    func rename(_ documentID: UUID, to title: String) async {
        do { try await documentStore.rename(documentID, to: title) }
        catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite(_ documentID: UUID, isFavorite: Bool) async {
        do { try await documentStore.setFavorite(documentID, isFavorite: isFavorite) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Borrado lógico. Los ficheros no se tocan: la papelera y su purga son de
    /// la Sprint 5.
    func moveToTrash(_ documentID: UUID) async {
        do { try await documentStore.moveToTrash(documentID) }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func savePageEdit(
        _ configuration: PageEditConfiguration,
        pageID: UUID,
        documentID: UUID
    ) async -> Bool {
        phase = .working(done: 0, total: 1)
        var didSave = false
        do {
            let assets = try await documentStore.pageAssetInfo(pageID: pageID, in: documentID)
            let fileStore = fileStore
            let rendered = try await Task.detached(priority: .userInitiated) {
                let data = try fileStore.read(fileName: assets.originalFileName, documentID: documentID)
                guard let source = Downsampler.fullImage(from: data)?.cgImage else {
                    throw ImageImportError.unreadable
                }
                let image = try PageRenderer.fullResolution(source, configuration: configuration)
                let processed = try ImageProcessor.encodeProcessed(image)
                let thumbnail = Downsampler.thumbnail(
                    from: processed,
                    maxPixelSize: ImageProcessor.thumbnailMaxPixelSize
                ).flatMap { try? ImageProcessor.encodeThumbnail($0) }
                return (processed, thumbnail)
            }.value

            // La página pudo borrarse mientras se renderizaba: comprobar que
            // sigue existiendo antes de escribir para no dejar ficheros huérfanos.
            _ = try await documentStore.pageAssetInfo(pageID: pageID, in: documentID)

            try fileStore.write(rendered.0, fileName: assets.processedFileName, documentID: documentID)
            if let thumbnail = rendered.1 {
                try fileStore.write(thumbnail, fileName: assets.thumbnailFileName, documentID: documentID)
            }
            do {
                try await documentStore.updatePage(pageID, in: documentID, configuration: configuration)
            } catch {
                try? fileStore.delete(fileName: assets.processedFileName, documentID: documentID)
                if rendered.1 != nil {
                    try? fileStore.delete(fileName: assets.thumbnailFileName, documentID: documentID)
                }
                throw error
            }
            ThumbnailCache.shared.removeValue(forKey: assets.thumbnailFileName)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
        return didSave
    }

    func reorderPages(_ pageIDs: [UUID], in documentID: UUID) async {
        do { try await documentStore.reorderPages(pageIDs, in: documentID) }
        catch { errorMessage = error.localizedDescription }
    }

    func deletePage(_ pageID: UUID, from documentID: UUID) async {
        do {
            let assets = try await documentStore.deletePage(pageID, in: documentID)
            for fileName in [assets.originalFileName, assets.processedFileName, assets.thumbnailFileName] {
                try? fileStore.delete(fileName: fileName, documentID: documentID)
            }
            ThumbnailCache.shared.removeValue(forKey: assets.thumbnailFileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Privado

    private func ingest(
        _ images: [SendableImage],
        documentID: UUID,
        startingIndex: Int,
        detectionMask: [Bool]
    ) async throws -> [PageRecord] {
        phase = .working(done: 0, total: images.count)

        // Se normaliza una sola vez por imagen aquí (necesario para detectar el
        // cuadrilátero) y se reutiliza en el ingest en lugar de repetir el
        // render de orientación por segunda vez.
        let (detectedQuads, normalizedImages): ([QuadPoints?], [CGImage?]) = await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: (Int, QuadPoints?, CGImage?).self) { group in
                for (index, image) in images.enumerated() {
                    guard detectionMask.indices.contains(index), detectionMask[index] else { continue }
                    group.addTask {
                        let normalized = ImageProcessor.normalized(image)
                        return (index, await DocumentQuadDetector.detect(in: normalized), normalized)
                    }
                }
                var quads = [QuadPoints?](repeating: nil, count: images.count)
                var normalized = [CGImage?](repeating: nil, count: images.count)
                for await (index, quad, image) in group {
                    quads[index] = quad
                    normalized[index] = image
                }
                return (quads, normalized)
            }
        }.value

        let ingestor = PageIngestor(fileStore: fileStore)
        let onProgress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in self?.phase = .working(done: done, total: total) }
        }

        return try await Task.detached(priority: .userInitiated) {
            try ingestor.ingest(
                images,
                documentID: documentID,
                startingIndex: startingIndex,
                detectedQuads: detectedQuads,
                normalizedImages: normalizedImages,
                onProgress: onProgress
            )
        }.value
    }
}
