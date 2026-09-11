import Foundation
import SwiftData

enum DocumentStoreError: Error {
    case documentNotFound(UUID)
    case folderNotFound(UUID)
}

/// Datos de archivo que el coordinador puede usar fuera del actor sin mover
/// modelos SwiftData entre hilos.
struct PageAssetInfo: Sendable, Equatable {
    let originalFileName: String
    let processedFileName: String
    let thumbnailFileName: String
}

/// Lo que el reconocimiento necesita saber de una página antes de empezar:
/// qué imagen leer y si ya gastó su unidad de la cuota mensual. Va aparte de
/// `PageAssetInfo` porque aquello describe ficheros que a veces hay que
/// borrar, y esto una decisión de cuota; mezclarlos confundiría las dos cosas.
struct PageOCRInfo: Sendable, Equatable {
    let processedFileName: String
    let ocrCounted: Bool
}

/// Resultado de OCR listo para persistir en una página concreta.
struct PageOCRUpdate: Sendable, Equatable {
    let pageID: UUID
    let text: String
    let boxes: [OCRBox]
}

/// Todo lo que necesita el exportador de una página. El OCR corre siempre
/// sobre `processedFileName` (ver `ScanCoordinator.runOCR`), así que las
/// cajas ya son relativas a esos píxeles exactos: no hace falta llevar
/// también la `PageEditConfiguration`, ni volver a renderizar nada.
struct PageExportInfo: Sendable, Equatable {
    let pageID: UUID
    let index: Int
    let processedFileName: String
    let ocrBoxes: [OCRBox]
}

/// Todo lo que necesita el exportador de un documento entero.
struct DocumentExportInfo: Sendable, Equatable {
    let documentID: UUID
    let title: String
    /// Ya en orden de presentación (`orderedPages`).
    let pages: [PageExportInfo]
}

/// Página de cualquier documento, para operaciones que recorren la
/// biblioteca entera (regenerar miniaturas) sin sacar modelos del actor.
struct PageThumbnailTarget: Sendable, Equatable {
    let documentID: UUID
    let pageID: UUID
    let processedFileName: String
    let thumbnailFileName: String
}

/// Escrituras de SwiftData fuera del hilo principal.
///
/// `@ModelActor` da un ejecutor propio y un `ModelContext` atado a él. Todo lo
/// que entra y sale son tipos `Sendable` sencillos —identificadores, cadenas,
/// `PageRecord`—; **nunca** modelos de SwiftData, que no se pueden pasar entre
/// actores. Las vistas vuelven a leer con `@Query` a partir del identificador.
@ModelActor
actor DocumentStore {

    /// Crea el documento y sus páginas. Devuelve el identificador para que la
    /// vista navegue a él.
    @discardableResult
    func createDocument(id: UUID = UUID(), title: String, records: [PageRecord]) throws -> UUID {
        let document = ScanDocument(id: id, title: title)
        modelContext.insert(document)

        for record in records {
            let page = makePage(from: record)
            page.document = document
            modelContext.insert(page)
        }

        try modelContext.save()
        return id
    }

    func appendPages(_ records: [PageRecord], to documentID: UUID) throws {
        let document = try fetchDocument(documentID)
        for record in records {
            let page = makePage(from: record)
            page.document = document
            modelContext.insert(page)
        }
        document.updatedAt = .now
        try modelContext.save()
    }

    func pageAssetInfo(pageID: UUID, in documentID: UUID) throws -> PageAssetInfo {
        let page = try fetchPage(pageID, in: documentID)
        return PageAssetInfo(
            originalFileName: page.originalFileName,
            processedFileName: page.processedFileName,
            thumbnailFileName: page.thumbnailFileName
        )
    }

    func updatePage(
        _ pageID: UUID,
        in documentID: UUID,
        configuration: PageEditConfiguration
    ) throws {
        let document = try fetchDocument(documentID)
        let page = try fetchPage(pageID, in: document)
        page.rotation = configuration.rotation
        page.filter = configuration.filter
        page.documentEnhancementIntensity = configuration.documentEnhancementIntensity
        page.quad = configuration.quad
        document.updatedAt = .now
        try modelContext.save()
    }

    func reorderPages(_ pageIDs: [UUID], in documentID: UUID) throws {
        let document = try fetchDocument(documentID)
        let pageByID = Dictionary(uniqueKeysWithValues: document.pages.map { ($0.id, $0) })
        guard pageIDs.count == document.pages.count,
              Set(pageIDs) == Set(pageByID.keys)
        else { throw DocumentStoreError.documentNotFound(documentID) }

        for (index, pageID) in pageIDs.enumerated() {
            pageByID[pageID]?.index = index
        }
        document.updatedAt = .now
        try modelContext.save()
    }

    /// Borra el registro y devuelve los assets que hay que eliminar después
    /// del `save`. Así un fallo de disco no puede dejar una página apuntando a
    /// ficheros que ya no existen.
    func deletePage(_ pageID: UUID, in documentID: UUID) throws -> PageAssetInfo {
        let document = try fetchDocument(documentID)
        let page = try fetchPage(pageID, in: document)
        let assets = PageAssetInfo(
            originalFileName: page.originalFileName,
            processedFileName: page.processedFileName,
            thumbnailFileName: page.thumbnailFileName
        )
        document.pages.removeAll { $0.id == pageID }
        modelContext.delete(page)
        for (index, remainingPage) in document.orderedPages.enumerated() {
            remainingPage.index = index
        }
        document.updatedAt = .now
        try modelContext.save()
        return assets
    }

    /// Primer índice libre, para añadir páginas sin pisar las que ya están.
    func nextPageIndex(for documentID: UUID) throws -> Int {
        let document = try fetchDocument(documentID)
        return (document.pages.map(\.index).max() ?? -1) + 1
    }

    @discardableResult
    func rename(_ documentID: UUID, to title: String) throws -> DocumentSearchSummary {
        let document = try fetchDocument(documentID)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            document.title = trimmed
            document.updatedAt = .now
            try modelContext.save()
        }
        return summary(of: document)
    }

    /// Persiste el resultado del OCR de una página y recalcula el texto de
    /// búsqueda del documento a partir de todas sus páginas. Se recalcula por
    /// completo en cada llamada —barato, es solo concatenar cadenas— así el
    /// documento va quedando buscable página a página en vez de todo de golpe.
    @discardableResult
    func setOCRResult(_ update: PageOCRUpdate, in documentID: UUID) throws -> DocumentSearchSummary {
        let document = try fetchDocument(documentID)
        let page = try fetchPage(update.pageID, in: document)
        page.ocrText = update.text
        page.ocrBoxes = update.boxes
        page.ocrFailed = false
        // La unidad de cuota se da por gastada aquí y no antes: si el
        // reconocimiento no llegó a completarse, no se cobra.
        page.ocrCounted = true
        page.ocrDeferred = false
        document.searchText = document.orderedPages
            .map(\.ocrText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        document.updatedAt = .now
        try modelContext.save()
        return summary(of: document)
    }

    func searchSummary(for documentID: UUID) throws -> DocumentSearchSummary {
        summary(of: try fetchDocument(documentID))
    }

    func setFavorite(_ documentID: UUID, isFavorite: Bool) throws {
        let document = try fetchDocument(documentID)
        document.isFavorite = isFavorite
        document.updatedAt = .now
        try modelContext.save()
    }

    /// Borrado lógico. Los ficheros siguen en disco hasta que la papelera se
    /// purgue (Sprint 5); así se puede restaurar.
    func moveToTrash(_ documentID: UUID) throws {
        let document = try fetchDocument(documentID)
        document.deletedAt = .now
        document.updatedAt = .now
        try modelContext.save()
    }

    @discardableResult
    func restoreFromTrash(_ documentID: UUID) throws -> DocumentSearchSummary {
        let document = try fetchDocument(documentID)
        document.deletedAt = nil
        document.updatedAt = .now
        try modelContext.save()
        return summary(of: document)
    }

    /// Igual que `moveToTrash` pero para varios documentos a la vez
    /// (selección múltiple en la biblioteca), en un único `save`.
    func moveToTrash(_ documentIDs: [UUID]) throws {
        let now = Date.now
        for id in documentIDs {
            guard let document = try? fetchDocument(id) else { continue }
            document.deletedAt = now
            document.updatedAt = now
        }
        try modelContext.save()
    }

    /// Borra el registro del documento de SwiftData (el `deleteRule: .cascade`
    /// de `ScanDocument.pages` se lleva las páginas). Los ficheros de disco no
    /// se tocan aquí: el llamador los borra con `FileStore` una vez que esto
    /// no puede fallar a mitad.
    func permanentlyDelete(_ documentID: UUID) throws {
        let document = try fetchDocument(documentID)
        modelContext.delete(document)
        try modelContext.save()
    }

    /// Documentos en la papelera desde antes de `cutoff`, listos para que el
    /// llamador borre sus ficheros y luego confirme el borrado del registro
    /// con `permanentlyDelete`.
    func expiredTrash(before cutoff: Date) throws -> [UUID] {
        let descriptor = FetchDescriptor<ScanDocument>(
            predicate: #Predicate { $0.deletedAt != nil }
        )
        return try modelContext.fetch(descriptor)
            .filter { ($0.deletedAt ?? .distantFuture) < cutoff }
            .map(\.id)
    }

    /// Todo lo que necesita `PDFExporter`/`ImageExporter` de un documento, en
    /// un único viaje al actor.
    func exportInfo(for documentID: UUID) throws -> DocumentExportInfo {
        let document = try fetchDocument(documentID)
        let pages = document.orderedPages.map {
            PageExportInfo(
                pageID: $0.id,
                index: $0.index,
                processedFileName: $0.processedFileName,
                ocrBoxes: $0.ocrBoxes
            )
        }
        return DocumentExportInfo(documentID: document.id, title: document.title, pages: pages)
    }

    /// Nombres de fichero de un documento, para poder borrarlos desde fuera sin
    /// sacar modelos del actor.
    func pageFileNames(for documentID: UUID) throws -> [String] {
        let document = try fetchDocument(documentID)
        return document.pages.flatMap {
            [$0.originalFileName, $0.processedFileName, $0.thumbnailFileName]
        }
    }

    // MARK: - Carpetas

    @discardableResult
    func createFolder(id: UUID = UUID(), name: String) throws -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxIndex = try modelContext.fetch(FetchDescriptor<ScanFolder>())
            .map(\.sortIndex)
            .max() ?? -1
        let folder = ScanFolder(id: id, name: trimmed.isEmpty ? name : trimmed, sortIndex: maxIndex + 1)
        modelContext.insert(folder)
        try modelContext.save()
        return id
    }

    func renameFolder(_ folderID: UUID, to name: String) throws {
        let folder = try fetchFolder(folderID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        folder.name = trimmed
        try modelContext.save()
    }

    /// Borra la carpeta. `deleteRule: .nullify` en `ScanFolder.documents` ya se
    /// encarga de dejar los documentos sin carpeta; no hay que tocarlos aquí.
    func deleteFolder(_ folderID: UUID) throws {
        let folder = try fetchFolder(folderID)
        modelContext.delete(folder)
        try modelContext.save()
    }

    /// `folderID` a `nil` saca el documento de cualquier carpeta.
    func moveDocument(_ documentID: UUID, toFolder folderID: UUID?) throws {
        let document = try fetchDocument(documentID)
        document.folder = try folderID.map(fetchFolder)
        document.updatedAt = .now
        try modelContext.save()
    }

    /// Igual que `moveDocument(_:toFolder:)` pero para varios documentos a la
    /// vez, en un único `save`.
    func moveDocuments(_ documentIDs: [UUID], toFolder folderID: UUID?) throws {
        let folder = try folderID.map(fetchFolder)
        let now = Date.now
        for id in documentIDs {
            guard let document = try? fetchDocument(id) else { continue }
            document.folder = folder
            document.updatedAt = now
        }
        try modelContext.save()
    }

    // MARK: - OCR

    func ocrPageInfo(pageID: UUID, in documentID: UUID) throws -> PageOCRInfo {
        let page = try fetchPage(pageID, in: documentID)
        return PageOCRInfo(processedFileName: page.processedFileName, ocrCounted: page.ocrCounted)
    }

    /// Marca que el reconocimiento de una página falló, para que la ficha del
    /// documento lo enseñe y ofrezca reintentar en vez de dejarlo en silencio.
    func setOCRFailed(_ pageID: UUID, in documentID: UUID) throws {
        let page = try fetchPage(pageID, in: documentID)
        page.ocrFailed = true
        page.ocrDeferred = false
        try modelContext.save()
    }

    /// Marca que la página se queda sin reconocer porque la cuota mensual del
    /// plan gratuito está agotada. No es un fallo y no se ofrece reintentar a
    /// mano: se resuelve sola al empezar el mes siguiente o al comprar Pro.
    func setOCRDeferred(_ pageID: UUID, in documentID: UUID) throws {
        let page = try fetchPage(pageID, in: documentID)
        page.ocrDeferred = true
        page.ocrFailed = false
        try modelContext.save()
    }

    /// Páginas que esperan cuota, agrupadas por documento y en orden de
    /// presentación, para reanudarlas cuando vuelve a haber.
    func deferredOCRPages() throws -> [UUID: [UUID]] {
        let documents = try modelContext.fetch(
            FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return documents.reduce(into: [UUID: [UUID]]()) { result, document in
            let pending = document.orderedPages.filter(\.ocrDeferred).map(\.id)
            guard !pending.isEmpty else { return }
            result[document.id] = pending
        }
    }

    /// Cuántas páginas de la biblioteca esperan cuota. Para el aviso de Ajustes.
    func deferredOCRPageCount() throws -> Int {
        try deferredOCRPages().values.reduce(0) { $0 + $1.count }
    }

    /// Nombres de fichero de todas las páginas de la biblioteca (documentos no
    /// borrados), para regenerar miniaturas desde Ajustes.
    func allThumbnailTargets() throws -> [PageThumbnailTarget] {
        let documents = try modelContext.fetch(
            FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return documents.flatMap { document in
            document.pages.map {
                PageThumbnailTarget(
                    documentID: document.id,
                    pageID: $0.id,
                    processedFileName: $0.processedFileName,
                    thumbnailFileName: $0.thumbnailFileName
                )
            }
        }
    }

    // MARK: - Privado

    private func makePage(from record: PageRecord) -> ScanPage {
        ScanPage(
            id: record.pageID,
            index: record.index,
            originalFileName: record.originalFileName,
            processedFileName: record.processedFileName,
            thumbnailFileName: record.thumbnailFileName,
            filter: record.filter,
            documentEnhancementIntensity: record.documentEnhancementIntensity,
            quad: record.quad
        )
    }

    private func fetchDocument(_ id: UUID) throws -> ScanDocument {
        var descriptor = FetchDescriptor<ScanDocument>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let document = try modelContext.fetch(descriptor).first else {
            throw DocumentStoreError.documentNotFound(id)
        }
        return document
    }

    private func fetchPage(_ pageID: UUID, in documentID: UUID) throws -> ScanPage {
        try fetchPage(pageID, in: fetchDocument(documentID))
    }

    private func fetchFolder(_ id: UUID) throws -> ScanFolder {
        var descriptor = FetchDescriptor<ScanFolder>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let folder = try modelContext.fetch(descriptor).first else {
            throw DocumentStoreError.folderNotFound(id)
        }
        return folder
    }

    private func fetchPage(_ pageID: UUID, in document: ScanDocument) throws -> ScanPage {
        guard let page = document.pages.first(where: { $0.id == pageID }) else {
            throw DocumentStoreError.documentNotFound(document.id)
        }
        return page
    }

    private func summary(of document: ScanDocument) -> DocumentSearchSummary {
        DocumentSearchSummary(
            documentID: document.id,
            title: document.title,
            searchText: document.searchText,
            createdAt: document.createdAt,
            updatedAt: document.updatedAt
        )
    }
}
