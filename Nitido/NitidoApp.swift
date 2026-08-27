import SwiftData
import SwiftUI

@main
struct NitidoApp: App {
    @State private var services: AppServices
    @State private var router = AppRouter()

    init() {
        _services = State(initialValue: AppServices.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            RootView(startupError: services.startupError)
                .environment(\.fileStore, services.fileStore)
                .environment(services.scanCoordinator)
                .environment(router)
        }
        .modelContainer(services.modelContainer)
    }
}

/// Composición de la app: se crea una vez al arrancar y se inyecta hacia abajo.
/// Inyección por inicializador y `.environment`; no hay contenedor de DI.
@MainActor
struct AppServices {
    let fileStore: any FileStoring
    let modelContainer: ModelContainer
    let scanCoordinator: ScanCoordinator
    /// Si el almacenamiento en disco falla se arranca en memoria para que la
    /// app siga siendo usable, pero el error se enseña; no se traga en silencio.
    let startupError: String?

    static func bootstrap() -> AppServices {
        do {
            let store = try LocalFileStore.makeDefault()
            let container = try ModelContainer.nitido(storeDirectory: store.root)
            return AppServices(
                fileStore: store,
                modelContainer: container,
                scanCoordinator: ScanCoordinator(modelContainer: container, fileStore: store),
                startupError: nil
            )
        } catch {
            let fallbackRoot = URL.temporaryDirectory
            let store = LocalFileStore(containerRoot: fallbackRoot)
            // Si ni siquiera el contenedor en memoria se puede crear, no hay app
            // que salvar: es un fallo de esquema, no de entorno.
            let container = try! ModelContainer.nitidoInMemory()
            return AppServices(
                fileStore: store,
                modelContainer: container,
                scanCoordinator: ScanCoordinator(modelContainer: container, fileStore: store),
                startupError: error.localizedDescription
            )
        }
    }
}

extension EnvironmentValues {
    @Entry var fileStore: any FileStoring = LocalFileStore(containerRoot: .temporaryDirectory)
}
