import PhotosUI
import SwiftData
import SwiftUI

enum LibraryLayout: String, CaseIterable {
    case grid
    case list
}

enum LibrarySort: String, CaseIterable {
    case date
    case name

    var label: String {
        switch self {
        case .date: String(localized: "library.sort.date", defaultValue: "Por fecha")
        case .name: String(localized: "library.sort.name", defaultValue: "Por nombre")
        }
    }
}

struct LibraryView: View {
    @Query(
        filter: #Predicate<ScanDocument> { $0.deletedAt == nil },
        sort: \ScanDocument.createdAt,
        order: .reverse
    )
    private var documents: [ScanDocument]

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(AppRouter.self) private var router
    @Environment(\.colorScheme) private var scheme

    @AppStorage("library.layout") private var layoutRaw = LibraryLayout.grid.rawValue
    @AppStorage("library.sort") private var sortRaw = LibrarySort.date.rawValue

    @State private var searchText = ""
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []

    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .grid }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .date }

    private var visibleDocuments: [ScanDocument] {
        let filtered = searchText.isEmpty
            ? documents
            : documents.filter {
                $0.title.localizedStandardContains(searchText)
                    || $0.searchText.localizedStandardContains(searchText)
            }

        switch sort {
        case .date: return filtered
        case .name: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.libraryPath) {
            content
                .dsScreenBackground()
                .navigationTitle(String(localized: "library.title", defaultValue: "Documentos"))
                .searchable(
                    text: $searchText,
                    prompt: Text(String(
                        localized: "library.searchPrompt",
                        defaultValue: "Buscar texto en documentos"
                    ))
                )
                .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
                .toolbar { toolbarContent }
                .overlay(alignment: .bottomTrailing) { scanButton }
                .overlay { progressOverlay }
        }
        .scanSources(
            isShowingCamera: $isShowingCamera,
            isShowingPhotoPicker: $isShowingPhotoPicker,
            isShowingFileImporter: $isShowingFileImporter,
            photoItems: $photoItems,
            destinationDocumentID: nil
        )
        .errorAlert(coordinator: coordinator)
        .onChange(of: coordinator.createdDocumentID) { _, newValue in
            guard let newValue else { return }
            // La captura acaba en el documento nuevo, no de vuelta en la lista.
            router.libraryPath = [newValue]
            coordinator.createdDocumentID = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibleDocuments.isEmpty {
            emptyState
        } else if layout == .grid {
            grid
        } else {
            list
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty
                    ? String(localized: "library.empty.title", defaultValue: "Ningún documento todavía")
                    : String(localized: "library.noResults.title", defaultValue: "Sin resultados"),
                systemImage: searchText.isEmpty ? "doc.viewfinder" : "magnifyingglass"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(searchText.isEmpty
                 ? String(localized: "library.empty.description",
                          defaultValue: "Escanea tu primer documento. Todo se procesa en este iPhone.")
                 : String(localized: "library.noResults.description",
                          defaultValue: "Prueba con otra palabra."))
            .font(DS.Typography.calloutText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DS.Spacing.x4),
                    GridItem(.flexible(), spacing: DS.Spacing.x4)
                ],
                spacing: DS.Spacing.x5
            ) {
                ForEach(visibleDocuments) { document in
                    NavigationLink(value: document.id) {
                        DocumentGridCell(document: document)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.screenGutter)
            .padding(.top, DS.Spacing.x2)
            // Hueco para que el botón flotante no tape la última fila.
            .padding(.bottom, DS.Spacing.x24)
        }
    }

    private var list: some View {
        List(visibleDocuments) { document in
            NavigationLink(value: document.id) {
                DocumentRow(document: document)
            }
            .listRowBackground(DS.ColorToken.card(scheme))
            .listRowSeparatorTint(DS.ColorToken.border(scheme))
        }
        .listStyle(.plain)
        .safeAreaPadding(.bottom, DS.Spacing.x16)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(String(localized: "library.sort", defaultValue: "Ordenar"), selection: $sortRaw) {
                    ForEach(LibrarySort.allCases, id: \.rawValue) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                Picker(String(localized: "library.layout", defaultValue: "Presentación"), selection: $layoutRaw) {
                    Label(String(localized: "library.layout.grid", defaultValue: "Cuadrícula"),
                          systemImage: "square.grid.2x2")
                        .tag(LibraryLayout.grid.rawValue)
                    Label(String(localized: "library.layout.list", defaultValue: "Lista"),
                          systemImage: "list.bullet")
                        .tag(LibraryLayout.list.rawValue)
                }
            } label: {
                Label(
                    String(localized: "library.options", defaultValue: "Opciones"),
                    systemImage: "slider.horizontal.3"
                )
            }
        }
    }

    private var scanButton: some View {
        ScanSourceMenu(
            isShowingCamera: $isShowingCamera,
            isShowingPhotoPicker: $isShowingPhotoPicker,
            isShowingFileImporter: $isShowingFileImporter
        ) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: DS.Typography.xl2, weight: .semibold))
                .foregroundStyle(DS.Brand.ctaPrimaryFG)
                .frame(width: 62, height: 62)
                .background(DS.ColorToken.primary(scheme))
                .clipShape(Circle())
                .dsShadow(.lg)
        }
        .accessibilityLabel(String(localized: "library.scan", defaultValue: "Escanear"))
        .padding(.trailing, DS.Spacing.screenGutter)
        .padding(.bottom, DS.Spacing.x5)
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if case .working(let done, let total) = coordinator.phase {
            ProcessingOverlay(done: done, total: total)
        }
    }
}
