import CoreSpotlight
import SwiftUI

enum AppTab: Hashable {
    case documents
    case folders
    case search
    case settings
}

struct RootView: View {
    let startupError: String?

    @Environment(\.colorScheme) private var scheme
    @Environment(AppRouter.self) private var router
    @Environment(ScanCoordinator.self) private var coordinator
    @State private var selectedTab: AppTab = .documents
    @State private var isShowingStartupError = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(String(localized: "tab.documents", defaultValue: "Documentos"),
                systemImage: "doc.text",
                value: AppTab.documents) {
                LibraryView()
            }

            Tab(String(localized: "tab.folders", defaultValue: "Carpetas"),
                systemImage: "folder",
                value: AppTab.folders) {
                NavigationStack { FoldersView() }
            }

            Tab(String(localized: "tab.search", defaultValue: "Buscar"),
                systemImage: "magnifyingglass",
                value: AppTab.search) {
                NavigationStack { SearchView() }
            }

            Tab(String(localized: "tab.settings", defaultValue: "Ajustes"),
                systemImage: "gearshape",
                value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(DS.ColorToken.primary(scheme))
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let documentID = SpotlightItemID.documentID(from: identifier)
            else { return }
            selectedTab = .documents
            router.openDocument(documentID)
        }
        .alert(
            String(localized: "startup.error.title", defaultValue: "No se pudo abrir el almacenamiento"),
            isPresented: $isShowingStartupError,
            actions: { Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {} },
            message: {
                Text(startupError ?? "")
            }
        )
        .task {
            isShowingStartupError = startupError != nil
        }
        .task {
            // Purga en segundo plano al arrancar, no bloquea el primer frame.
            await coordinator.purgeExpiredTrash()
        }
    }
}
