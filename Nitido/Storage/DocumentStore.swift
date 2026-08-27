import Foundation
import SwiftData

enum DocumentStoreError: Error {
    case documentNotFound(UUID)
}

/// Datos de archivo que el coordinador puede usar fuera del actor sin mover
/// modelos SwiftData entre hilos.
struct PageAssetInfo: Sendable, Equatable {
    let originalFileName: String
    let processedFileName: String
    let thumbnailFileName: String
}

/// Resultado de OCR listo para persistir en una página concreta.
struct PageOCRUpdate: Sendable, Equatable {
    let pageID: UUID
    let text: String
    let boxes: [OCRBox]
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

    /// Nombres de fichero de un documento, para poder borrarlos desde fuera sin
    /// sacar modelos del actor.
    func pageFileNames(for documentID: UUID) throws -> [String] {
        let document = try fetchDocument(documentID)
        return document.pages.flatMap {
            [$0.originalFileName, $0.processedFileName, $0.thumbnailFileName]
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
