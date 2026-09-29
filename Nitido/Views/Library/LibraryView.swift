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
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.colorScheme) private var scheme
    @Environment(\.fileStore) private var fileStore

    @AppStorage("library.layout") private var layoutRaw = LibraryLayout.grid.rawValue
    @AppStorage("library.sort") private var sortRaw = LibrarySort.date.rawValue
    @AppStorage("library.favoritesOnly") private var favoritesOnly = false

    @State private var searchText = ""
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var documentPendingTrash: ScanDocument?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var isConfirmingBatchTrash = false
    @State private var isExportingSelection = false
    @State private var batchExportURLs: [URL] = []
    @State private var batchExportError: String?
    @State private var requestedFeature: ProFeature?

    private var layout: LibraryLayout { LibraryLayout(rawValue: layoutRaw) ?? .grid }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .date }

    private var visibleDocuments: [ScanDocument] {
        var filtered = searchText.isEmpty
            ? documents
            : documents.filter {
                $0.title.localizedStandardContains(searchText)
                    || $0.searchText.localizedStandardContains(searchText)
            }

        if favoritesOnly {
            filtered = filtered.filter(\.isFavorite)
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
                .overlay(alignment: .bottomTrailing) { if !isSelecting { scanButton } }
                .safeAreaInset(edge: .bottom) { if isSelecting { selectionActionBar } }
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
        .proFeatureNotice($requestedFeature)
        .confirmationDialog(
            String(localized: "document.delete.title", defaultValue: "¿Mover a la papelera?"),
            isPresented: Binding(
                get: { documentPendingTrash != nil },
                set: { if !$0 { documentPendingTrash = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "document.delete.confirm", defaultValue: "Mover a la papelera"),
                   role: .destructive) {
                guard let document = documentPendingTrash else { return }
                Task { await coordinator.moveToTrash(document.id) }
                documentPendingTrash = nil
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                documentPendingTrash = nil
            }
        } message: {
            Text(String(
                localized: "document.delete.message",
                defaultValue: "Podrás restaurarlo desde la papelera."
            ))
        }
        .confirmationDialog(
            String(localized: "document.delete.title", defaultValue: "¿Mover a la papelera?"),
            isPresented: $isConfirmingBatchTrash,
            titleVisibility: .visible
        ) {
            Button(String(localized: "document.delete.confirm", defaultValue: "Mover a la papelera"),
                   role: .destructive) {
                let ids = Array(selectedIDs)
                Task { await coordinator.moveToTrash(ids) }
                endSelection()
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "document.delete.message",
                defaultValue: "Podrás restaurarlo desde la papelera."
            ))
        }
        .alert(
            String(localized: "export.error.title", defaultValue: "No se pudo exportar"),
            isPresented: Binding(
                get: { batchExportError != nil },
                set: { if !$0 { batchExportError = nil } }
            )
        ) {
            Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {}
        } message: {
            Text(batchExportError ?? "")
        }
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
        let isFiltering = !searchText.isEmpty || favoritesOnly
        return ContentUnavailableView {
            Label(
                isFiltering
                    ? String(localized: "library.noResults.title", defaultValue: "Sin resultados")
                    : String(localized: "library.empty.title", defaultValue: "Ningún documento todavía"),
                systemImage: isFiltering ? "magnifyingglass" : "doc.viewfinder"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(isFiltering
                 ? String(localized: "library.noResults.description",
                          defaultValue: "Prueba con otra palabra.")
                 : String(localized: "library.empty.description",
                          defaultValue: "Escanea tu primer documento. Todo se procesa en este iPhone."))
            .font(DS.Typography.calloutText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: DS.Layout.adaptiveGridColumns,
                spacing: DS.Spacing.x5
            ) {
                ForEach(visibleDocuments) { document in
                    if isSelecting {
                        Button { toggleSelection(document.id) } label: {
                            DocumentGridCell(document: document)
                                .overlay(alignment: .topTrailing) { selectionBadge(for: document.id) }
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: document.id) {
                            DocumentGridCell(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { documentContextMenu(for: document) }
                    }
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
            if isSelecting {
                Button { toggleSelection(document.id) } label: {
                    HStack {
                        DocumentRow(document: document)
                        Spacer()
                        selectionBadge(for: document.id)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(DS.ColorToken.card(scheme))
                .listRowSeparatorTint(DS.ColorToken.border(scheme))
            } else {
                NavigationLink(value: document.id) {
                    DocumentRow(document: document)
                }
                .listRowBackground(DS.ColorToken.card(scheme))
                .listRowSeparatorTint(DS.ColorToken.border(scheme))
                .contextMenu { documentContextMenu(for: document) }
            }
        }
        .listStyle(.plain)
        .safeAreaPadding(.bottom, isSelecting ? DS.Spacing.x24 : DS.Spacing.x16)
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    @ViewBuilder
    private func selectionBadge(for id: UUID) -> some View {
        let isSelected = selectedIDs.contains(id)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isSelected ? DS.Brand.ctaPrimaryFG : DS.ColorToken.mutedForeground(scheme),
                isSelected ? DS.ColorToken.primary(scheme) : DS.ColorToken.card(scheme)
            )
            .padding(DS.Spacing.x2)
    }

    @ViewBuilder
    private func documentContextMenu(for document: ScanDocument) -> some View {
        Button {
            Task { await coordinator.toggleFavorite(document.id, isFavorite: !document.isFavorite) }
        } label: {
            Label(
                document.isFavorite
                    ? String(localized: "document.unfavorite", defaultValue: "Quitar de favoritos")
                    : String(localized: "document.favorite", defaultValue: "Añadir a favoritos"),
                systemImage: document.isFavorite ? "star.slash" : "star"
            )
        }
        FolderMoveMenu(document: document)
        Divider()
        Button(role: .destructive) {
            documentPendingTrash = document
        } label: {
            Label(String(localized: "document.delete", defaultValue: "Mover a la papelera"), systemImage: "trash")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !visibleDocuments.isEmpty {
                Button(isSelecting
                       ? String(localized: "common.done", defaultValue: "Hecho")
                       : String(localized: "library.select", defaultValue: "Seleccionar")) {
                    if isSelecting { endSelection() } else { isSelecting = true }
                }
            }
        }
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
                Toggle(isOn: $favoritesOnly) {
                    Label(String(localized: "library.favoritesOnly", defaultValue: "Solo favoritos"), systemImage: "star")
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

    private func endSelection() {
        isSelecting = false
        selectedIDs = []
    }

    private var selectionActionBar: some View {
        HStack(spacing: DS.Spacing.x2) {
            Text(String(localized: "library.selection.count", defaultValue: "\(selectedIDs.count) seleccionados"))
                .font(DS.Typography.captionText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            Spacer()

            BatchFolderMoveMenu(documentIDs: Array(selectedIDs)) { endSelection() }
                .disabled(selectedIDs.isEmpty)

            if isExportingSelection {
                ProgressView().controlSize(.small)
            } else if !batchExportURLs.isEmpty {
                ShareLink(items: batchExportURLs) {
                    Image(systemName: "square.and.arrow.up")
                }
            } else {
                Button {
                    Task { await exportSelection() }
                } label: {
                    HStack(spacing: DS.Spacing.x1) {
                        Image(systemName: "square.and.arrow.up")
                        if !entitlements.allows(.batchExport) { ProBadge() }
                    }
                }
                .disabled(selectedIDs.isEmpty)
                .accessibilityLabel(String(localized: "library.selection.export", defaultValue: "Exportar la selección"))
                .proGated(.batchExport, isAllowed: entitlements.allows(.batchExport)) {
                    requestedFeature = $0
                }
            }

            Button(role: .destructive) {
                isConfirmingBatchTrash = true
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, DS.Spacing.screenGutter)
        .padding(.vertical, DS.Spacing.x3)
        .background(.bar)
    }

    /// Exporta cada documento seleccionado como PDF, con los ajustes por
    /// defecto (ajustar a la imagen, compresión alta, sin contraseña), y los
    /// ofrece juntos en un único `ShareLink` — igual patrón que la exportación
    /// de imágenes de un solo documento (Sprint 4): varios ficheros, sin zip.
    private func exportSelection() async {
        // El botón ya está bloqueado sin Pro; esto lo vuelve a comprobar aquí
        // para que el gate no dependa de que ninguna pantalla futura se olvide.
        guard entitlements.allows(.batchExport) else { return }
        isExportingSelection = true
        batchExportURLs = []
        batchExportError = nil
        defer { isExportingSelection = false }

        let compressionLevel = UserDefaults.standard.string(forKey: "settings.exportCompression")
            .flatMap(PDFCompressionLevel.init(rawValue:)) ?? .high
        var urls: [URL] = []
        for documentID in selectedIDs {
            do {
                let info = try await coordinator.exportInfo(for: documentID)
                let options = PDFExportOptions(pageSizeMode: .fitToImage, compressionLevel: compressionLevel)
                let fileStore = fileStore
                let fileName = "\(ImageExporter.sanitize(info.title))-\(documentID.uuidString.prefix(4)).pdf"
                // Generar y escribir en la misma tarea de fondo: exportar varios
                // documentos seguidos desde el `MainActor` bloquea la biblioteca
                // tantas veces como documentos haya seleccionados.
                let url = try await Task.detached(priority: .userInitiated) { () -> URL in
                    let data = try PDFExporter.export(info, options: options, fileStore: fileStore)
                    let url = URL.temporaryDirectory.appending(path: fileName, directoryHint: .notDirectory)
                    try data.write(to: url, options: .atomic)
                    return url
                }.value
                urls.append(url)
            } catch {
                batchExportError = error.localizedDescription
                return
            }
        }
        batchExportURLs = urls
    }
}
