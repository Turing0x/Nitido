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
    @Environment(StoreManager.self) private var storeManager
    @Environment(Entitlements.self) private var entitlements
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
        // En iPad la barra de pestañas pasa a barra lateral; en iPhone no cambia.
        .tabViewStyle(.sidebarAdaptable)
        .tint(DS.ColorToken.primary(scheme))
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                  let documentID = SpotlightItemID.documentID(from: identifier)
            else { return }
            selectedTab = .documents
            router.openDocument(documentID)
        }
        .onOpenURL { url in
            // «Copiar a Nítido» desde otra app: entra como un documento más.
            selectedTab = .documents
            coordinator.receiveIncomingFile(url)
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
        .task {
            // El estado Pro ya viene de caché, así que esto solo lo corrige.
            // Después se recogen las páginas que se quedaron esperando cuota,
            // que es lo que hace que el mes nuevo empiece solo.
            await storeManager.refreshEntitlements()
            await coordinator.resumeDeferredOCR()
        }
        .onChange(of: entitlements.isPro) { _, isPro in
            // Comprar o restaurar levanta el límite al instante: lo que quedó
            // aplazado se reconoce sin que haya que reabrir la app.
            guard isPro else { return }
            Task { await coordinator.resumeDeferredOCR() }
        }
    }
}
