import AVFoundation
import CoreGraphics
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

    /// Progreso del OCR en segundo plano, por documento. A diferencia de
    /// `phase`, nunca bloquea: es un indicador discreto en la ficha del
    /// documento mientras el resto de la app sigue usable.
    struct OCRProgress: Equatable {
        let done: Int
        let total: Int
    }

    private(set) var phase: Phase = .idle
    /// Documento recién creado, para que la biblioteca navegue a él.
    var createdDocumentID: UUID?
    var errorMessage: String?
    private(set) var ocrProgress: [UUID: OCRProgress] = [:]

    private let documentStore: DocumentStore
    private let fileStore: any FileStoring
    private let textRecognizer = TextRecognizer()
    private let spotlightIndexer = SpotlightIndexer()

    init(modelContainer: ModelContainer, fileStore: any FileStoring) {
        self.documentStore = DocumentStore(modelContainer: modelContainer)
        self.fileStore = fileStore
    }

    /// Ejecuta trabajo de disco fuera del hilo principal.
    ///
    /// `ScanCoordinator` está en el `MainActor`, así que **toda** llamada
    /// síncrona a `fileStore` desde sus métodos corre en el hilo principal:
    /// escribir el JPEG procesado de una página son varios megabytes, y purgar
    /// una papelera llena son cientos de borrados. Todo eso pasa por aquí.
    /// Solo para trabajo cuyo fallo ya se ignora a propósito (`try?`): un
    /// borrado que no se puede completar deja un directorio huérfano, que no es
    /// motivo para enseñar nada al usuario. El trabajo que sí puede fallar de
    /// forma relevante lanza su propia `Task.detached`, para no tener que
    /// pelearse con `rethrows` —`Task.value` lanza por su cuenta, así que el
    /// compilador nunca podría probar que el único error viene del closure—.
    private func onFileStore(
        priority: TaskPriority = .utility,
        _ work: @escaping @Sendable (any FileStoring) -> Void
    ) async {
        let fileStore = fileStore
        await Task.detached(priority: priority) {
            work(fileStore)
        }.value
    }

    // MARK: - Captura e importación

    func createDocument(from images: [SendableImage], detectDocuments: Bool = false) async {
        await createDocument(from: ImageImporter.provider(for: images, detectsDocument: detectDocuments))
    }

    /// - Returns: el identificador del documento creado, o `nil` si falló.
    @discardableResult
    func createDocument(from provider: PageBatchProvider) async -> UUID? {
        guard provider.count > 0 else { return nil }
        let documentID = UUID()
        let title = ScanDocument.defaultTitle()
        var created: UUID?

        do {
            let records = try await ingest(provider, documentID: documentID, startingIndex: 0)
            try await documentStore.createDocument(id: documentID, title: title, records: records)
            createdDocumentID = documentID
            created = documentID
            runOCR(for: documentID, pageIDs: records.map(\.pageID))
        } catch {
            // Si algo falla a mitad, el directorio a medio escribir no se queda
            // ocupando sitio ni ensuciando el cálculo de espacio.
            await onFileStore { try? $0.deleteDocumentDirectory(for: documentID) }
            errorMessage = error.localizedDescription
        }
        phase = .idle
        return created
    }

    func addPages(_ images: [SendableImage], to documentID: UUID, detectDocuments: Bool = false) async {
        await addPages(
            ImageImporter.provider(for: images, detectsDocument: detectDocuments),
            to: documentID
        )
    }

    func addPages(_ provider: PageBatchProvider, to documentID: UUID) async {
        guard provider.count > 0 else { return }
        do {
            let startingIndex = try await documentStore.nextPageIndex(for: documentID)
            let records = try await ingest(provider, documentID: documentID, startingIndex: startingIndex)
            try await documentStore.appendPages(records, to: documentID)
            runOCR(for: documentID, pageIDs: records.map(\.pageID))
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
            // Se conservan los datos comprimidos; la decodificación ocurre lote
            // a lote dentro de la ingesta, fuera del hilo principal.
            let provider = ImageImporter.provider(forImageData: payloads)
            if let documentID {
                await addPages(provider, to: documentID)
            } else {
                await createDocument(from: provider)
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    /// Cada fichero elegido entra como su propio proveedor y se ingiere por
    /// separado: el primero crea o abre el documento y el resto le añaden
    /// páginas. Así nunca hay más de un lote de páginas vivo, por muchos
    /// ficheros o muy largos que sean.
    func importFromFiles(result: Result<[URL], Error>, into documentID: UUID? = nil) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            phase = .working(done: 0, total: urls.count)
            do {
                // Abrir el fichero (y contar las páginas de un PDF) sale del
                // hilo principal; rasterizar ya va por lotes dentro de `ingest`.
                var providers: [PageBatchProvider] = []
                for url in urls {
                    let provider = try await Task.detached(priority: .userInitiated) {
                        try ImageImporter.provider(forFileAt: url)
                    }.value
                    providers.append(provider)
                }

                var targetID = documentID
                for provider in providers {
                    if let targetID {
                        await addPages(provider, to: targetID)
                    } else {
                        // El resto de ficheros se añaden al documento que acaba
                        // de crear el primero, no crean uno por fichero.
                        guard let created = await createDocument(from: provider) else { break }
                        targetID = created
                    }
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
        do {
            let summary = try await documentStore.rename(documentID, to: title)
            await spotlightIndexer.index(summary)
        } catch { errorMessage = error.localizedDescription }
    }

    func toggleFavorite(_ documentID: UUID, isFavorite: Bool) async {
        do { try await documentStore.setFavorite(documentID, isFavorite: isFavorite) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Borrado lógico. Los ficheros no se tocan: la papelera y su purga son de
    /// la Sprint 5. El documento desaparece del buscador del sistema de
    /// inmediato, aunque todavía se pueda restaurar.
    func moveToTrash(_ documentID: UUID) async {
        do {
            try await documentStore.moveToTrash(documentID)
            await spotlightIndexer.deindex([documentID])
        } catch { errorMessage = error.localizedDescription }
    }

    func restoreFromTrash(_ documentID: UUID) async {
        do {
            let summary = try await documentStore.restoreFromTrash(documentID)
            await spotlightIndexer.index(summary)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Selección múltiple en la biblioteca.
    func moveToTrash(_ documentIDs: [UUID]) async {
        guard !documentIDs.isEmpty else { return }
        do {
            try await documentStore.moveToTrash(documentIDs)
            await spotlightIndexer.deindex(documentIDs)
        } catch { errorMessage = error.localizedDescription }
    }

    func moveDocuments(_ documentIDs: [UUID], toFolder folderID: UUID?) async {
        guard !documentIDs.isEmpty else { return }
        do { try await documentStore.moveDocuments(documentIDs, toFolder: folderID) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Borra un documento de la papelera para siempre: registro y ficheros.
    /// El registro se borra primero porque no puede fallar a medias; si el
    /// borrado de ficheros falla después, el documento ya no aparece en
    /// ningún sitio y el directorio huérfano no ocupa gran cosa.
    func permanentlyDelete(_ documentID: UUID) async {
        do {
            try await documentStore.permanentlyDelete(documentID)
            await onFileStore { try? $0.deleteDocumentDirectory(for: documentID) }
            await spotlightIndexer.deindex([documentID])
        } catch { errorMessage = error.localizedDescription }
    }

    /// Purga los documentos en papelera desde hace más de 30 días. Se llama
    /// una vez al arrancar (`RootView`); no bloquea ni enseña progreso.
    func purgeExpiredTrash() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        guard let expired = try? await documentStore.expiredTrash(before: cutoff), !expired.isEmpty else { return }

        for documentID in expired {
            try? await documentStore.permanentlyDelete(documentID)
        }

        // Los borrados de disco van juntos y fuera del hilo principal: se llama
        // al arrancar, y una papelera con cientos de documentos caducados
        // congelaba el primer frame borrándolos uno a uno en el `MainActor`.
        await onFileStore(priority: .background) { store in
            for documentID in expired {
                try? store.deleteDocumentDirectory(for: documentID)
            }
        }
    }

    /// Regenera todas las miniaturas de la biblioteca a partir del procesado
    /// de cada página, para el botón de Ajustes. Devuelve cuántas se
    /// regeneraron.
    @discardableResult
    func regenerateThumbnails() async -> Int {
        guard let targets = try? await documentStore.allThumbnailTargets(), !targets.isEmpty else { return 0 }
        let fileStore = fileStore
        var regenerated = 0
        for target in targets {
            let didRegenerate: Bool = await Task.detached(priority: .utility) {
                guard let processedData = try? fileStore.read(
                    fileName: target.processedFileName, documentID: target.documentID
                ) else { return false }
                guard let thumbnail = autoreleasepool(invoking: {
                    Downsampler.thumbnail(from: processedData, maxPixelSize: ImageProcessor.thumbnailMaxPixelSize)
                }), let thumbnailData = try? ImageProcessor.encodeThumbnail(thumbnail) else { return false }
                return (try? fileStore.write(
                    thumbnailData, fileName: target.thumbnailFileName, documentID: target.documentID
                )) != nil
            }.value
            if didRegenerate {
                ThumbnailCache.shared.removeValue(forKey: target.thumbnailFileName)
                regenerated += 1
            }
        }
        return regenerated
    }

    // MARK: - Carpetas

    @discardableResult
    func createFolder(name: String) async -> UUID? {
        do { return try await documentStore.createFolder(name: name) }
        catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func renameFolder(_ folderID: UUID, to name: String) async {
        do { try await documentStore.renameFolder(folderID, to: name) }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteFolder(_ folderID: UUID) async {
        do { try await documentStore.deleteFolder(folderID) }
        catch { errorMessage = error.localizedDescription }
    }

    func moveDocument(_ documentID: UUID, toFolder folderID: UUID?) async {
        do { try await documentStore.moveDocument(documentID, toFolder: folderID) }
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
            let rendered = try await Task.detached(priority: .userInitiated) { () -> (Data, Data?) in
                let data = try fileStore.read(fileName: assets.originalFileName, documentID: documentID)
                guard let source = Downsampler.fullImage(from: data)?.cgImage else {
                    throw ImageImportError.unreadable
                }
                return try autoreleasepool {
                    let image = try PageRenderer.fullResolution(source, configuration: configuration)
                    let processed = try ImageProcessor.encodeProcessed(image)
                    let thumbnail = Downsampler.thumbnail(
                        from: processed,
                        maxPixelSize: ImageProcessor.thumbnailMaxPixelSize
                    ).flatMap { try? ImageProcessor.encodeThumbnail($0) }
                    return (processed, thumbnail)
                }
            }.value

            // La página pudo borrarse mientras se renderizaba: comprobar que
            // sigue existiendo antes de escribir para no dejar ficheros huérfanos.
            _ = try await documentStore.pageAssetInfo(pageID: pageID, in: documentID)

            // El procesado a resolución completa son varios megabytes: la
            // escritura sale del hilo principal igual que el render.
            try await Task.detached(priority: .userInitiated) {
                try fileStore.write(rendered.0, fileName: assets.processedFileName, documentID: documentID)
                if let thumbnail = rendered.1 {
                    try fileStore.write(thumbnail, fileName: assets.thumbnailFileName, documentID: documentID)
                }
            }.value
            do {
                try await documentStore.updatePage(pageID, in: documentID, configuration: configuration)
            } catch {
                let hadThumbnail = rendered.1 != nil
                await onFileStore { store in
                    try? store.delete(fileName: assets.processedFileName, documentID: documentID)
                    if hadThumbnail {
                        try? store.delete(fileName: assets.thumbnailFileName, documentID: documentID)
                    }
                }
                throw error
            }
            ThumbnailCache.shared.removeValue(forKey: assets.thumbnailFileName)
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        phase = .idle
        // El procesado ha cambiado (rotación, recorte o filtro): las cajas de
        // OCR guardadas quedarían relativas a píxeles que ya no existen. Se
        // reconoce de nuevo esta página, igual que tras una captura, para que
        // el PDF exportado (Sprint 4) no dibuje el texto invisible desplazado.
        if didSave {
            runOCR(for: documentID, pageIDs: [pageID])
        }
        return didSave
    }

    /// Datos de exportación de un documento entero, en un único viaje al
    /// actor. Ninguna vista toca `documentStore` directamente.
    func exportInfo(for documentID: UUID) async throws -> DocumentExportInfo {
        try await documentStore.exportInfo(for: documentID)
    }

    func reorderPages(_ pageIDs: [UUID], in documentID: UUID) async {
        do { try await documentStore.reorderPages(pageIDs, in: documentID) }
        catch { errorMessage = error.localizedDescription }
    }

    func deletePage(_ pageID: UUID, from documentID: UUID) async {
        do {
            let assets = try await documentStore.deletePage(pageID, in: documentID)
            await onFileStore { store in
                for fileName in [assets.originalFileName, assets.processedFileName, assets.thumbnailFileName] {
                    try? store.delete(fileName: fileName, documentID: documentID)
                }
            }
            ThumbnailCache.shared.removeValue(forKey: assets.thumbnailFileName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Privado

    /// Reintenta el reconocimiento de una sola página, desde la ficha del
    /// documento, cuando `ScanPage.ocrFailed` lo pide.
    func retryOCR(pageID: UUID, documentID: UUID) {
        runOCR(for: documentID, pageIDs: [pageID])
    }

    /// Reconoce el texto de un lote de páginas recién guardadas, una a una,
    /// en segundo plano. No forma parte de `phase`: una página que falla no
    /// aborta el documento ni bloquea nada. El fallo se marca en
    /// `ScanPage.ocrFailed`, que la ficha enseña con un botón de reintentar.
    private func runOCR(for documentID: UUID, pageIDs: [UUID]) {
        guard !pageIDs.isEmpty else { return }
        ocrProgress[documentID] = OCRProgress(done: 0, total: pageIDs.count)

        let documentStore = documentStore
        let fileStore = fileStore
        let recognizer = textRecognizer
        let indexer = spotlightIndexer
        let (languages, automaticDetection) = ocrLanguagePreference.recognitionParameters

        Task.detached(priority: .utility) { [weak self] in
            var didRecognizeAnyPage = false

            for (offset, pageID) in pageIDs.enumerated() {
                do {
                    let assets = try await documentStore.pageAssetInfo(pageID: pageID, in: documentID)
                    let data = try fileStore.read(fileName: assets.processedFileName, documentID: documentID)
                    // Una imagen que no decodifica es un fallo de la página, igual
                    // que un fallo de Vision: antes caía por un `if let` sin `else`
                    // y no se marcaba, así que la ficha no ofrecía reintentarla.
                    guard let cgImage = autoreleasepool(invoking: {
                        Downsampler.fullImage(from: data)?.cgImage
                    }) else {
                        throw ImageImportError.unreadable
                    }
                    let result = try await recognizer.recognize(
                        cgImage,
                        languages: languages,
                        automaticallyDetectsLanguage: automaticDetection
                    )
                    let update = PageOCRUpdate(pageID: pageID, text: result.text, boxes: result.boxes)
                    try await documentStore.setOCRResult(update, in: documentID)
                    didRecognizeAnyPage = true
                } catch {
                    try? await documentStore.setOCRFailed(pageID, in: documentID)
                }
                let done = offset + 1
                await MainActor.run {
                    self?.ocrProgress[documentID] = done == pageIDs.count ? nil : OCRProgress(done: done, total: pageIDs.count)
                }
            }

            // La indexación va **fuera** del bucle y lee el resumen actual del
            // documento. Antes colgaba de `offset == pageIDs.count - 1` dentro
            // del `do`: si la última página del lote fallaba, el documento entero
            // se quedaba sin indexar para siempre —con las otras páginas
            // reconocidas perfectamente— y no había error que lo delatara.
            if didRecognizeAnyPage,
               let summary = try? await documentStore.searchSummary(for: documentID) {
                await indexer.index(summary)
            }
        }
    }

    /// Filtro con el que arranca una página recién capturada sin cuadrilátero
    /// detectado (cámara: VisionKit ya la recorta, así que aquí solo decide el
    /// realce). Ajustable en Ajustes; `UserDefaults` directamente porque
    /// `@AppStorage` no combina con `@Observable`.
    private var defaultFilter: PageFilter {
        UserDefaults.standard.string(forKey: "settings.defaultFilter")
            .flatMap(PageFilter.init(rawValue:)) ?? .original
    }

    private var ocrLanguagePreference: OCRLanguagePreference {
        UserDefaults.standard.string(forKey: "settings.ocrLanguage")
            .flatMap(OCRLanguagePreference.init(rawValue:)) ?? .automatic
    }

    /// Ingiere una fuente de páginas **lote a lote**.
    ///
    /// Antes esto materializaba el lote entero: un `withTaskGroup` lanzaba una
    /// tarea de Vision por cada imagen sin límite de concurrencia y devolvía dos
    /// arrays completos —los originales y sus versiones normalizadas—, así que
    /// un PDF de cuarenta páginas mantenía ochenta imágenes a resolución
    /// completa vivas a la vez. Ahora solo vive el lote en curso: se escribe en
    /// disco, se suelta y se pide el siguiente.
    private func ingest(
        _ provider: PageBatchProvider,
        documentID: UUID,
        startingIndex: Int
    ) async throws -> [PageRecord] {
        let total = provider.count
        phase = .working(done: 0, total: total)

        let ingestor = PageIngestor(fileStore: fileStore)
        let defaultFilter = defaultFilter
        let detects = provider.detectsDocument

        var records: [PageRecord] = []
        records.reserveCapacity(total)

        for range in provider.batchRanges {
            let batchStart = startingIndex + range.lowerBound
            let doneBefore = range.lowerBound
            // El progreso se sigue informando página a página, no lote a lote.
            let onProgress: @Sendable (Int, Int) -> Void = { [weak self] done, _ in
                Task { @MainActor in
                    self?.phase = .working(done: doneBefore + done, total: total)
                }
            }
            // Materializar el lote va **dentro** de la tarea de fondo: hacerlo
            // aquí decodificaría las imágenes en el hilo principal.
            let materialize = provider.batch

            let batchRecords = try await Task.detached(priority: .userInitiated) { () -> [PageRecord] in
                let images = try materialize(range)
                let (quads, normalized) = await ScanCoordinator.detectedQuads(in: images, enabled: detects)
                return try ingestor.ingest(
                    images,
                    documentID: documentID,
                    startingIndex: batchStart,
                    detectedQuads: quads,
                    normalizedImages: normalized,
                    defaultFilter: defaultFilter,
                    onProgress: onProgress
                )
            }.value

            records.append(contentsOf: batchRecords)
            phase = .working(done: records.count, total: total)
        }

        return records
    }

    /// Detecta el cuadrilátero de cada página del lote y devuelve, de paso, la
    /// imagen ya normalizada: se necesita para detectar y se reutiliza en la
    /// ingesta, en vez de repetir el render de orientación una segunda vez.
    ///
    /// La concurrencia está acotada por el tamaño del lote
    /// (`PageBatchProvider.batchSize`), que es justo lo que antes no lo estaba.
    nonisolated private static func detectedQuads(
        in images: [SendableImage],
        enabled: Bool
    ) async -> ([QuadPoints?], [CGImage?]) {
        guard enabled else {
            return (
                [QuadPoints?](repeating: nil, count: images.count),
                [CGImage?](repeating: nil, count: images.count)
            )
        }

        return await withTaskGroup(of: (Int, QuadPoints?, CGImage?).self) { group in
            for (index, image) in images.enumerated() {
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
    }
}
