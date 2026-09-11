import SwiftData
import SwiftUI

/// Documentos de una carpeta. Mismo estilo de cuadrícula que `LibraryView`,
/// pero sin escaneo ni orden: eso ya lo hace la biblioteca general, aquí solo
/// se cura el contenido de la carpeta.
struct FolderDetailView: View {
    let folderID: UUID

    @Query private var folders: [ScanFolder]
    @Query private var documents: [ScanDocument]

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isConfirmingDelete = false

    init(folderID: UUID) {
        self.folderID = folderID
        _folders = Query(filter: #Predicate<ScanFolder> { $0.id == folderID })
        _documents = Query(
            filter: #Predicate<ScanDocument> { $0.folder?.id == folderID && $0.deletedAt == nil },
            sort: \ScanDocument.createdAt,
            order: .reverse
        )
    }

    private var folder: ScanFolder? { folders.first }

    var body: some View {
        Group {
            if let folder {
                content
                    .navigationTitle(folder.name)
            } else {
                ContentUnavailableView(
                    String(localized: "folder.missing.title", defaultValue: "Carpeta no disponible"),
                    systemImage: "questionmark.folder"
                )
            }
        }
        .dsScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .errorAlert(coordinator: coordinator)
        .alert(
            String(localized: "folder.rename.title", defaultValue: "Renombrar carpeta"),
            isPresented: $isRenaming
        ) {
            TextField(String(localized: "folder.name.field", defaultValue: "Nombre"), text: $draftName)
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
            Button(String(localized: "common.save", defaultValue: "Guardar")) {
                Task { await coordinator.renameFolder(folderID, to: draftName) }
            }
        }
        .confirmationDialog(
            String(localized: "folder.delete.title", defaultValue: "¿Eliminar carpeta?"),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(String(localized: "folder.delete.confirm", defaultValue: "Eliminar carpeta"), role: .destructive) {
                Task {
                    await coordinator.deleteFolder(folderID)
                    dismiss()
                }
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "folder.delete.message",
                defaultValue: "Los documentos no se borran: se quedan sin carpeta."
            ))
        }
    }

    @ViewBuilder
    private var content: some View {
        if documents.isEmpty {
            ContentUnavailableView {
                Label(
                    String(localized: "folder.empty.title", defaultValue: "Carpeta vacía"),
                    systemImage: "folder"
                )
                .font(DS.Typography.sectionTitle)
            } description: {
                Text(String(
                    localized: "folder.empty.description",
                    defaultValue: "Mueve documentos aquí desde su ficha o desde la biblioteca."
                ))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DS.Spacing.x4),
                        GridItem(.flexible(), spacing: DS.Spacing.x4)
                    ],
                    spacing: DS.Spacing.x5
                ) {
                    ForEach(documents) { document in
                        NavigationLink(value: document.id) {
                            DocumentGridCell(document: document)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { documentContextMenu(for: document) }
                    }
                }
                .padding(.horizontal, DS.Spacing.screenGutter)
                .padding(.vertical, DS.Spacing.x2)
            }
            .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
        }
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    draftName = folder?.name ?? ""
                    isRenaming = true
                } label: {
                    Label(String(localized: "folder.rename", defaultValue: "Renombrar"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label(String(localized: "folder.delete", defaultValue: "Eliminar carpeta"), systemImage: "trash")
                }
            } label: {
                Label(String(localized: "common.more", defaultValue: "Más"), systemImage: "ellipsis.circle")
            }
            .disabled(folder == nil)
        }
    }
}
