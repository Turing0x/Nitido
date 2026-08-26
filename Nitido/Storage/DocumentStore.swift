import Foundation
import SwiftData

enum DocumentStoreError: Error {
    case documentNotFound(UUID)
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

    /// Primer índice libre, para añadir páginas sin pisar las que ya están.
    func nextPageIndex(for documentID: UUID) throws -> Int {
        let document = try fetchDocument(documentID)
        return (document.pages.map(\.index).max() ?? -1) + 1
    }

    func rename(_ documentID: UUID, to title: String) throws {
        let document = try fetchDocument(documentID)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document.title = trimmed
        document.updatedAt = .now
        try modelContext.save()
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

    func restoreFromTrash(_ documentID: UUID) throws {
        let document = try fetchDocument(documentID)
        document.deletedAt = nil
        document.updatedAt = .now
        try modelContext.save()
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
            thumbnailFileName: record.thumbnailFileName
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
}
