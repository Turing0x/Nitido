import Foundation

/// Tipo de imagen que guarda una página en disco.
enum PageAssetKind: String, Sendable, CaseIterable {
    case original
    case processed
    case thumbnail

    /// Prefijo del nombre de fichero, según el layout acordado:
    /// `original-<pageUUID>.heic`, `processed-<pageUUID>.jpg`, `thumb-<pageUUID>.jpg`.
    var prefix: String {
        switch self {
        case .original: "original"
        case .processed: "processed"
        case .thumbnail: "thumb"
        }
    }
}

enum FileStoreError: Error, Equatable {
    case fileNotFound(String)
    case invalidFileName(String)
}

/// Único punto del código que toca `FileManager`.
/// Si algún día se añade sincronización, se sustituye aquí y en ningún otro sitio.
protocol FileStoring: Sendable {
    /// Raíz de datos de la app: `.../Application Support/Nitido`.
    var root: URL { get }

    func documentDirectory(for documentID: UUID) -> URL
    func url(forFileName fileName: String, documentID: UUID) -> URL

    @discardableResult
    func createDocumentDirectory(for documentID: UUID) throws -> URL

    @discardableResult
    func write(_ data: Data, fileName: String, documentID: UUID) throws -> URL

    func read(fileName: String, documentID: UUID) throws -> Data
    func fileExists(fileName: String, documentID: UUID) -> Bool
    func delete(fileName: String, documentID: UUID) throws
    func deleteDocumentDirectory(for documentID: UUID) throws
    func sizeOnDisk() throws -> Int64
}

extension FileStoring {
    /// Construye el nombre de fichero de una página. El nombre es **relativo**;
    /// nunca se persiste una ruta absoluta.
    func fileName(for kind: PageAssetKind, pageID: UUID, fileExtension: String) -> String {
        "\(kind.prefix)-\(pageID.uuidString.lowercased()).\(fileExtension)"
    }
}

/// Implementación local, sobre el contenedor de la app.
struct LocalFileStore: FileStoring {
    let root: URL
    private let documentsRoot: URL

    /// - Parameter containerRoot: normalmente `Application Support`. Se inyecta
    ///   para poder ejecutar los tests contra un directorio temporal y para
    ///   simular un cambio de contenedor.
    init(containerRoot: URL) {
        self.root = containerRoot.appending(path: "Nitido", directoryHint: .isDirectory)
        self.documentsRoot = root.appending(path: "Documents", directoryHint: .isDirectory)
    }

    /// Store por defecto de la app.
    static func makeDefault() throws -> LocalFileStore {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let store = LocalFileStore(containerRoot: appSupport)
        try store.prepareRoot()
        return store
    }

    /// Crea la raíz y le aplica protección de datos. Aquí dentro va a haber
    /// DNIs y nóminas: si el iPhone se pierde con la pantalla bloqueada, estos
    /// ficheros deben ser ilegibles. `.completeUnlessOpen` permite que un
    /// fichero ya abierto (una exportación en curso) siga funcionando si la
    /// pantalla se bloquea a mitad.
    func prepareRoot() throws {
        try createDirectory(at: root)
        try createDirectory(at: documentsRoot)
    }

    func documentDirectory(for documentID: UUID) -> URL {
        documentsRoot.appending(path: documentID.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    func url(forFileName fileName: String, documentID: UUID) -> URL {
        documentDirectory(for: documentID).appending(path: fileName, directoryHint: .notDirectory)
    }

    @discardableResult
    func createDocumentDirectory(for documentID: UUID) throws -> URL {
        let directory = documentDirectory(for: documentID)
        try prepareRoot()
        try createDirectory(at: directory)
        return directory
    }

    @discardableResult
    func write(_ data: Data, fileName: String, documentID: UUID) throws -> URL {
        try validate(fileName)
        let directory = try createDocumentDirectory(for: documentID)
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])

        // Las miniaturas se regeneran a partir del procesado, así que no tienen
        // por qué ocupar sitio en la copia de seguridad de iCloud. Los
        // originales y los procesados sí entran en la copia.
        if fileName.hasPrefix(PageAssetKind.thumbnail.prefix) {
            try excludeFromBackup(url)
        }
        return url
    }

    func read(fileName: String, documentID: UUID) throws -> Data {
        try validate(fileName)
        let url = self.url(forFileName: fileName, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw FileStoreError.fileNotFound(fileName)
        }
        return try Data(contentsOf: url)
    }

    func fileExists(fileName: String, documentID: UUID) -> Bool {
        guard (try? validate(fileName)) != nil else { return false }
        let url = self.url(forFileName: fileName, documentID: documentID)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func delete(fileName: String, documentID: UUID) throws {
        try validate(fileName)
        let url = self.url(forFileName: fileName, documentID: documentID)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func deleteDocumentDirectory(for documentID: UUID) throws {
        let directory = documentDirectory(for: documentID)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Bytes ocupados por todo lo que guarda la app en disco.
    func sizeOnDisk() throws -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Privado

    private func createDirectory(at url: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path(percentEncoded: false)) {
            try manager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
        } else {
            try manager.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: url.path(percentEncoded: false)
            )
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    /// Un nombre de fichero es exactamente eso: sin separadores ni saltos hacia
    /// arriba. Cualquier otra cosa indica que alguien ha guardado una ruta.
    private func validate(_ fileName: String) throws {
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              fileName != ".",
              fileName != ".."
        else {
            throw FileStoreError.invalidFileName(fileName)
        }
    }
}
