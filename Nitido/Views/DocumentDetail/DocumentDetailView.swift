import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DocumentDetailView: View {
    let documentID: UUID

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @Query private var documents: [ScanDocument]

    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var isConfirmingDelete = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false
    @State private var isShowingFileImporter = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isReorderingPages = false
    @State private var provisionalPageIDs: [UUID] = []
    @State private var draggingPageID: UUID?
    @State private var pagePendingDeletion: UUID?

    init(documentID: UUID) {
        self.documentID = documentID
        _documents = Query(filter: #Predicate<ScanDocument> { $0.id == documentID })
    }

    private var document: ScanDocument? { documents.first }

    var body: some View {
        Group {
            if let document {
                pageGrid(for: document)
                    .navigationTitle(document.title)
            } else {
                ContentUnavailableView(
                    String(localized: "document.missing.title", defaultValue: "Documento no disponible"),
                    systemImage: "questionmark.folder"
                )
            }
        }
        .dsScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .scanSources(
            isShowingCamera: $isShowingCamera,
            isShowingPhotoPicker: $isShowingPhotoPicker,
            isShowingFileImporter: $isShowingFileImporter,
            photoItems: $photoItems,
            destinationDocumentID: documentID
        )
        .errorAlert(coordinator: coordinator)
        .overlay {
            if case .working(let done, let total) = coordinator.phase {
                ProcessingOverlay(done: done, total: total)
            }
        }
        .alert(
            String(localized: "document.rename.title", defaultValue: "Renombrar documento"),
            isPresented: $isRenaming
        ) {
            TextField(
                String(localized: "document.rename.field", defaultValue: "Título"),
                text: $draftTitle
            )
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
            Button(String(localized: "common.save", defaultValue: "Guardar")) {
                Task { await coordinator.rename(documentID, to: draftTitle) }
            }
        }
        .confirmationDialog(
            String(localized: "document.delete.title", defaultValue: "¿Mover a la papelera?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "document.delete.confirm", defaultValue: "Mover a la papelera"),
                   role: .destructive) {
                Task {
                    await coordinator.moveToTrash(documentID)
                    dismiss()
                }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "document.delete.message",
                defaultValue: "Podrás restaurarlo desde la papelera."
            ))
        }
        .confirmationDialog(
            String(localized: "page.delete.title", defaultValue: "¿Eliminar página?"),
            isPresented: Binding(
                get: { pagePendingDeletion != nil },
                set: { if !$0 { pagePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "page.delete.confirm", defaultValue: "Eliminar página"), role: .destructive) {
                guard let pageID = pagePendingDeletion else { return }
                provisionalPageIDs.removeAll { $0 == pageID }
                Task { await coordinator.deletePage(pageID, from: documentID) }
                pagePendingDeletion = nil
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                pagePendingDeletion = nil
            }
        } message: {
            Text(String(localized: "page.delete.message", defaultValue: "Esta acción elimina la página y sus imágenes."))
        }
    }

    private func pageGrid(for document: ScanDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x4) {
                Text(String(
                    localized: "document.pageCount",
                    defaultValue: "\(document.pages.count) páginas"
                ))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                .padding(.horizontal, DS.Spacing.screenGutter)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DS.Spacing.x4),
                        GridItem(.flexible(), spacing: DS.Spacing.x4)
                    ],
                    spacing: DS.Spacing.x5
                ) {
                    ForEach(presentedPages(for: document)) { page in
                        pageCell(page, in: document)
                    }
                    if !isReorderingPages {
                        addPageCell
                    }
                }
                .padding(.horizontal, DS.Spacing.screenGutter)
            }
            .padding(.vertical, DS.Spacing.x4)
        }
    }

    @ViewBuilder
    private func pageCell(_ page: ScanPage, in document: ScanDocument) -> some View {
        if isReorderingPages {
            reorderablePageCell(page, in: document)
        } else {
            NavigationLink {
                PageEditorView(documentID: documentID, pageID: page.id)
            } label: {
                pagePreview(page)
            }
            .buttonStyle(.plain)
        }
    }

    private func pagePreview(_ page: ScanPage) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            PageCard {
                PageThumbnail(
                    documentID: documentID,
                    thumbnailFileName: page.thumbnailFileName,
                    processedFileName: page.processedFileName,
                    revision: pageRevision(page)
                )
            }

            Text(String(localized: "document.page", defaultValue: "Página \(page.index + 1)"))
                .font(DS.Typography.captionText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
    }

    private func reorderablePageCell(_ page: ScanPage, in document: ScanDocument) -> some View {
        pagePreview(page)
            .overlay(alignment: .topTrailing) {
                Button(role: .destructive) {
                    pagePendingDeletion = page.id
                } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, DS.ColorToken.destructive(scheme))
                }
                .padding(DS.Spacing.x2)
                .accessibilityLabel(String(localized: "page.delete", defaultValue: "Eliminar página"))
            }
            .opacity(draggingPageID == page.id ? 0.45 : 1)
            .onDrag {
                draggingPageID = page.id
                return NSItemProvider(object: page.id.uuidString as NSString)
            }
            .onDrop(
                of: [UTType.plainText],
                delegate: PageReorderDropDelegate(
                    targetID: page.id,
                    pageIDs: $provisionalPageIDs,
                    draggingPageID: $draggingPageID,
                    onCommit: { pageIDs in
                        Task { await coordinator.reorderPages(pageIDs, in: documentID) }
                    }
                )
            )
    }

    /// Firma de las propiedades de la página que afectan a su miniatura, para
    /// que solo se recargue la página editada y no todas las del documento.
    private func pageRevision(_ page: ScanPage) -> TimeInterval {
        var hasher = Hasher()
        hasher.combine(page.rotation)
        hasher.combine(page.filterRaw)
        hasher.combine(page.documentEnhancementIntensity)
        hasher.combine(page.quadData)
        return TimeInterval(hasher.finalize())
    }

    private func presentedPages(for document: ScanDocument) -> [ScanPage] {
        let ordered = document.orderedPages
        guard isReorderingPages, !provisionalPageIDs.isEmpty else { return ordered }
        let pagesByID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        return provisionalPageIDs.compactMap { pagesByID[$0] }
    }

    private var addPageCell: some View {
        ScanSourceMenu(
            isShowingCamera: $isShowingCamera,
            isShowingPhotoPicker: $isShowingPhotoPicker,
            isShowingFileImporter: $isShowingFileImporter
        ) {
            PageCard(dashed: true) {
                VStack(spacing: DS.Spacing.x2) {
                    Image(systemName: "plus")
                        .font(.system(size: DS.Typography.xl2))
                    Text(String(localized: "document.addPage", defaultValue: "Añadir página"))
                        .font(DS.Typography.captionText)
                }
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    draftTitle = document?.title ?? ""
                    isRenaming = true
                } label: {
                    Label(String(localized: "document.rename", defaultValue: "Renombrar"),
                          systemImage: "pencil")
                }

                Button {
                    guard let document else { return }
                    Task { await coordinator.toggleFavorite(documentID, isFavorite: !document.isFavorite) }
                } label: {
                    Label(
                        document?.isFavorite == true
                            ? String(localized: "document.unfavorite", defaultValue: "Quitar de favoritos")
                            : String(localized: "document.favorite", defaultValue: "Añadir a favoritos"),
                        systemImage: document?.isFavorite == true ? "star.slash" : "star"
                    )
                }

                Divider()

                Button {
                    isReorderingPages.toggle()
                    draggingPageID = nil
                    provisionalPageIDs = isReorderingPages ? (document?.orderedPages.map(\.id) ?? []) : []
                } label: {
                    Label(
                        isReorderingPages
                            ? String(localized: "page.reorder.done", defaultValue: "Terminar de reordenar")
                            : String(localized: "page.reorder", defaultValue: "Reordenar páginas"),
                        systemImage: isReorderingPages ? "checkmark" : "arrow.left.arrow.right"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label(String(localized: "document.delete", defaultValue: "Mover a la papelera"),
                          systemImage: "trash")
                }
            } label: {
                Label(String(localized: "common.more", defaultValue: "Más"), systemImage: "ellipsis.circle")
            }
            .disabled(document == nil)
        }
    }
}
