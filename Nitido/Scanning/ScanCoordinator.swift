import AVFoundation
import Foundation
import PhotosUI
import SwiftData
import SwiftUI

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

    func createDocument(from images: [SendableImage]) async {
        guard !images.isEmpty else { return }
        let documentID = UUID()
        let title = ScanDocument.defaultTitle()

        do {
            let records = try await ingest(images, documentID: documentID, startingIndex: 0)
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

    func addPages(_ images: [SendableImage], to documentID: UUID) async {
        guard !images.isEmpty else { return }
        do {
            let startingIndex = try await documentStore.nextPageIndex(for: documentID)
            let records = try await ingest(images, documentID: documentID, startingIndex: startingIndex)
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
                await addPages(images, to: documentID)
            } else {
                await createDocument(from: images)
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
                let images = try await Task.detached(priority: .userInitiated) {
                    try urls.flatMap { try ImageImporter.images(fromFileAt: $0) }
                }.value

                if let documentID {
                    await addPages(images, to: documentID)
                } else {
                    await createDocument(from: images)
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

    // MARK: - Privado

    private func ingest(
        _ images: [SendableImage],
        documentID: UUID,
        startingIndex: Int
    ) async throws -> [PageRecord] {
        phase = .working(done: 0, total: images.count)

        let ingestor = PageIngestor(fileStore: fileStore)
        let onProgress: @Sendable (Int, Int) -> Void = { [weak self] done, total in
            Task { @MainActor in self?.phase = .working(done: done, total: total) }
        }

        return try await Task.detached(priority: .userInitiated) {
            try ingestor.ingest(
                images,
                documentID: documentID,
                startingIndex: startingIndex,
                onProgress: onProgress
            )
        }.value
    }
}
