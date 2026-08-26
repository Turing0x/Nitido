import PhotosUI
import SwiftData
import SwiftUI

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
                    ForEach(document.orderedPages) { page in
                        pageCell(page)
                    }
                    addPageCell
                }
                .padding(.horizontal, DS.Spacing.screenGutter)
            }
            .padding(.vertical, DS.Spacing.x4)
        }
    }

    private func pageCell(_ page: ScanPage) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            PageCard {
                PageThumbnail(
                    documentID: documentID,
                    thumbnailFileName: page.thumbnailFileName,
                    processedFileName: page.processedFileName
                )
            }

            Text(String(localized: "document.page", defaultValue: "Página \(page.index + 1)"))
                .font(DS.Typography.captionText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
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
