import Foundation
import SwiftData

extension Schema {
    /// Esquema actual. Al añadir un modelo hay que añadirlo aquí y, si cambia
    /// la forma de uno existente, crear un `VersionedSchema` + `MigrationPlan`.
    static let nitido = Schema([
        ScanDocument.self,
        ScanPage.self,
        ScanFolder.self
    ])
}

extension ModelContainer {
    /// Contenedor de la app. El store vive junto a las imágenes, dentro de
    /// `Application Support/Nitido`, para que todo el estado de la app esté en
    /// un único directorio protegido.
    static func nitido(storeDirectory: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: .nitido,
            url: storeDirectory.appending(path: "Nitido.store", directoryHint: .notDirectory)
        )
        return try ModelContainer(for: .nitido, configurations: configuration)
    }

    /// Contenedor en memoria, para previews y tests.
    static func nitidoInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: .nitido, isStoredInMemoryOnly: true)
        return try ModelContainer(for: .nitido, configurations: configuration)
    }
}
