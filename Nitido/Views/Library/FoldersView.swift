import SwiftData
import SwiftUI

struct FoldersView: View {
    @Query(sort: \ScanFolder.sortIndex) private var folders: [ScanFolder]

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme

    @State private var isCreating = false
    @State private var draftName = ""
    @State private var folderPendingRename: ScanFolder?
    @State private var folderPendingDeletion: ScanFolder?

    var body: some View {
        Group {
            if folders.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "folders.title", defaultValue: "Carpetas"))
        .navigationDestination(for: UUID.self) { FolderDetailView(folderID: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftName = ""
                    isCreating = true
                } label: {
                    Label(String(localized: "folder.new", defaultValue: "Nueva carpeta"), systemImage: "folder.badge.plus")
                }
            }
        }
        .errorAlert(coordinator: coordinator)
        .alert(
            String(localized: "folder.new", defaultValue: "Nueva carpeta"),
            isPresented: $isCreating
        ) {
            TextField(String(localized: "folder.name.field", defaultValue: "Nombre"), text: $draftName)
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {}
            Button(String(localized: "common.create", defaultValue: "Crear")) {
                Task { await coordinator.createFolder(name: draftName) }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert(
            String(localized: "folder.rename.title", defaultValue: "Renombrar carpeta"),
            isPresented: Binding(
                get: { folderPendingRename != nil },
                set: { if !$0 { folderPendingRename = nil } }
            )
        ) {
            TextField(String(localized: "folder.name.field", defaultValue: "Nombre"), text: $draftName)
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                folderPendingRename = nil
            }
            Button(String(localized: "common.save", defaultValue: "Guardar")) {
                guard let folder = folderPendingRename else { return }
                Task { await coordinator.renameFolder(folder.id, to: draftName) }
                folderPendingRename = nil
            }
        }
        .confirmationDialog(
            String(localized: "folder.delete.title", defaultValue: "¿Eliminar carpeta?"),
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "folder.delete.confirm", defaultValue: "Eliminar carpeta"), role: .destructive) {
                guard let folder = folderPendingDeletion else { return }
                Task { await coordinator.deleteFolder(folder.id) }
                folderPendingDeletion = nil
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                folderPendingDeletion = nil
            }
        } message: {
            Text(String(
                localized: "folder.delete.message",
                defaultValue: "Los documentos no se borran: se quedan sin carpeta."
            ))
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                String(localized: "folders.empty.title", defaultValue: "Carpetas"),
                systemImage: "folder"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(String(localized: "folders.empty.description", defaultValue: "Aún no has creado ninguna carpeta."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        } actions: {
            Button(String(localized: "folder.new", defaultValue: "Nueva carpeta")) {
                draftName = ""
                isCreating = true
            }
        }
    }

    private var list: some View {
        List(folders) { folder in
            NavigationLink(value: folder.id) {
                folderRow(folder)
            }
            .listRowBackground(DS.ColorToken.card(scheme))
            .listRowSeparatorTint(DS.ColorToken.border(scheme))
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    folderPendingDeletion = folder
                } label: {
                    Label(String(localized: "folder.delete", defaultValue: "Eliminar carpeta"), systemImage: "trash")
                }
                Button {
                    draftName = folder.name
                    folderPendingRename = folder
                } label: {
                    Label(String(localized: "folder.rename", defaultValue: "Renombrar"), systemImage: "pencil")
                }
                .tint(DS.ColorToken.primary(scheme))
            }
        }
        .listStyle(.plain)
    }

    private func folderRow(_ folder: ScanFolder) -> some View {
        HStack(spacing: DS.Spacing.x3) {
            Image(systemName: "folder.fill")
                .foregroundStyle(DS.ColorToken.primary(scheme))
                .font(.system(size: DS.Typography.xl))

            Text(folder.name)
                .font(DS.Typography.rowTitle)
                .foregroundStyle(DS.ColorToken.foreground(scheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(String(
                localized: "folder.documentCount",
                defaultValue: "\(activeDocumentCount(in: folder)) documentos"
            ))
            .font(DS.Typography.captionText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .padding(.vertical, DS.Spacing.x1)
        .accessibilityElement(children: .combine)
    }

    private func activeDocumentCount(in folder: ScanFolder) -> Int {
        folder.documents.filter { $0.deletedAt == nil }.count
    }
}

#Preview {
    NavigationStack { FoldersView() }
}
