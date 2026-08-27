import Foundation

/// Ruta de navegación compartida entre `RootView` y `LibraryView`.
///
/// `LibraryView` tiene su propio `NavigationStack`, pero el deep link de
/// Spotlight llega a `RootView`, fuera de esa jerarquía. Este router es el
/// punto en común: se inyecta una sola vez desde `NitidoApp` y ambas vistas
/// leen/escriben el mismo camino.
@MainActor
@Observable
final class AppRouter {
    var libraryPath: [UUID] = []

    func openDocument(_ id: UUID) {
        libraryPath = [id]
    }
}
