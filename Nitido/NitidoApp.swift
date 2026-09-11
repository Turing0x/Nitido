import SwiftData
import SwiftUI

@main
struct NitidoApp: App {
    @State private var services: AppServices?
    @State private var bootstrapFailure: String?
    @State private var router = AppRouter()

    init() {
        switch AppServices.bootstrap() {
        case .ready(let services):
            _services = State(initialValue: services)
            _bootstrapFailure = State(initialValue: nil)
        case .failed(let message):
            _services = State(initialValue: nil)
            _bootstrapFailure = State(initialValue: message)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let services {
                RootView(startupError: services.startupError)
                    .environment(\.fileStore, services.fileStore)
                    .environment(services.scanCoordinator)
                    .environment(router)
                    .modelContainer(services.modelContainer)
            } else {
                // Ni siquiera el contenedor en memoria se pudo crear. Antes esto
                // era un `try!`: la app se cerraba al instante y en el informe de
                // fallo solo aparecía un `fatalError` dentro del `init` de la App,
                // sin nada que un usuario pudiera contar ni un desarrollador
                // diagnosticar. Una pantalla explícita convierte el cierre en un
                // fallo reportable.
                StartupFailureView(message: bootstrapFailure ?? "")
            }
        }
    }
}

/// Composición de la app: se crea una vez al arrancar y se inyecta hacia abajo.
/// Inyección por inicializador y `.environment`; no hay contenedor de DI.
@MainActor
struct AppServices {

    /// Resultado del arranque. `failed` solo ocurre si el esquema de SwiftData
    /// está roto —ni siquiera se puede abrir en memoria—, que es un fallo de
    /// programación, no de entorno. Se representa igualmente en vez de abortar.
    enum Bootstrap {
        case ready(AppServices)
        case failed(String)
    }

    let fileStore: any FileStoring
    let modelContainer: ModelContainer
    let scanCoordinator: ScanCoordinator
    /// Si el almacenamiento en disco falla se arranca en memoria para que la
    /// app siga siendo usable, pero el error se enseña; no se traga en silencio.
    let startupError: String?

    static func bootstrap() -> Bootstrap {
        do {
            let store = try LocalFileStore.makeDefault()
            let container = try ModelContainer.nitido(storeDirectory: store.root)
            return .ready(AppServices(
                fileStore: store,
                modelContainer: container,
                scanCoordinator: ScanCoordinator(modelContainer: container, fileStore: store),
                startupError: nil
            ))
        } catch {
            return inMemoryFallback(after: error)
        }
    }

    /// El disco no se pudo abrir. Se arranca en memoria para que la app siga
    /// siendo usable (el usuario puede escanear y exportar, aunque no se guarde
    /// nada), enseñando el error de disco original.
    private static func inMemoryFallback(after diskError: Error) -> Bootstrap {
        let store = LocalFileStore(containerRoot: .temporaryDirectory)
        do {
            let container = try ModelContainer.nitidoInMemory()
            return .ready(AppServices(
                fileStore: store,
                modelContainer: container,
                scanCoordinator: ScanCoordinator(modelContainer: container, fileStore: store),
                startupError: diskError.localizedDescription
            ))
        } catch {
            return .failed("\(diskError.localizedDescription)\n\n\(error.localizedDescription)")
        }
    }
}

extension EnvironmentValues {
    @Entry var fileStore: any FileStoring = LocalFileStore(containerRoot: .temporaryDirectory)
}
