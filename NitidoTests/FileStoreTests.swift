import Foundation
import Testing
@testable import Nitido

@Suite("FileStore")
struct FileStoreTests {

    /// Cada test trabaja en su propio contenedor temporal.
    private func makeStore() throws -> (LocalFileStore, URL) {
        let root = URL.temporaryDirectory
            .appending(path: "NitidoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LocalFileStore(containerRoot: root)
        try store.prepareRoot()
        return (store, root)
    }

    @Test("crea el directorio de un documento")
    func createsDocumentDirectory() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let directory = try store.createDocumentDirectory(for: documentID)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false),
                                               isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(directory.lastPathComponent == documentID.uuidString.lowercased())
    }

    @Test("escribe, lee y borra un fichero")
    func writeReadDelete() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let pageID = UUID()
        let name = store.fileName(for: .processed, pageID: pageID, fileExtension: "jpg")
        let payload = Data("factura".utf8)

        try store.write(payload, fileName: name, documentID: documentID)
        #expect(store.fileExists(fileName: name, documentID: documentID))
        #expect(try store.read(fileName: name, documentID: documentID) == payload)

        try store.delete(fileName: name, documentID: documentID)
        #expect(!store.fileExists(fileName: name, documentID: documentID))
    }

    @Test("leer un fichero que no existe da fileNotFound")
    func readMissingFile() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: FileStoreError.fileNotFound("no-existe.jpg")) {
            try store.read(fileName: "no-existe.jpg", documentID: UUID())
        }
    }

    @Test("rechaza nombres que en realidad son rutas")
    func rejectsPathsAsFileNames() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: FileStoreError.self) {
            try store.write(Data(), fileName: "../fuera.jpg", documentID: UUID())
        }
    }

    @Test("borrar el documento se lleva sus ficheros")
    func deletesDocumentDirectory() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let pageID = UUID()
        let name = store.fileName(for: .original, pageID: pageID, fileExtension: "heic")
        try store.write(Data("x".utf8), fileName: name, documentID: documentID)

        try store.deleteDocumentDirectory(for: documentID)

        #expect(!FileManager.default.fileExists(
            atPath: store.documentDirectory(for: documentID).path(percentEncoded: false)
        ))
    }

    /// El caso que de verdad importa: el contenedor de la app cambia de UUID
    /// entre instalaciones. Como solo se guarda el nombre del fichero, un store
    /// apuntando a otra raíz debe resolver la ruta igual de bien.
    @Test("la ruta se reconstruye tras un cambio de contenedor")
    func survivesContainerChange() throws {
        let (oldStore, oldRoot) = try makeStore()
        let (newStore, newRoot) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: oldRoot)
            try? FileManager.default.removeItem(at: newRoot)
        }

        let documentID = UUID()
        let pageID = UUID()
        let name = oldStore.fileName(for: .thumbnail, pageID: pageID, fileExtension: "jpg")
        let payload = Data("miniatura".utf8)
        try oldStore.write(payload, fileName: name, documentID: documentID)

        // Simula la migración: el directorio del documento se mueve al
        // contenedor nuevo; el nombre guardado en SwiftData no cambia.
        try newStore.createDocumentDirectory(for: documentID)
        try FileManager.default.removeItem(at: newStore.documentDirectory(for: documentID))
        try FileManager.default.moveItem(
            at: oldStore.documentDirectory(for: documentID),
            to: newStore.documentDirectory(for: documentID)
        )

        #expect(newStore.fileExists(fileName: name, documentID: documentID))
        #expect(try newStore.read(fileName: name, documentID: documentID) == payload)
        #expect(!oldStore.fileExists(fileName: name, documentID: documentID))
    }

    @Test("las miniaturas quedan excluidas de la copia de seguridad")
    func thumbnailsExcludedFromBackup() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let pageID = UUID()
        let thumbName = store.fileName(for: .thumbnail, pageID: pageID, fileExtension: "jpg")
        let processedName = store.fileName(for: .processed, pageID: pageID, fileExtension: "jpg")

        let thumbURL = try store.write(Data("t".utf8), fileName: thumbName, documentID: documentID)
        let processedURL = try store.write(Data("p".utf8), fileName: processedName, documentID: documentID)

        #expect(try thumbURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try processedURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)
    }

    @Test("sizeOnDisk suma lo escrito")
    func sizeOnDiskGrows() throws {
        let (store, root) = try makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let before = try store.sizeOnDisk()
        try store.write(Data(repeating: 0, count: 32_768),
                        fileName: store.fileName(for: .original, pageID: UUID(), fileExtension: "heic"),
                        documentID: UUID())
        #expect(try store.sizeOnDisk() > before)
    }
}
