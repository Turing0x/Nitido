import SwiftData
import SwiftUI

/// Submenú reutilizable para mover un documento de carpeta. Vale igual dentro
/// de un `Menu` (toolbar de la ficha) que dentro de un `.contextMenu`
/// (biblioteca y carpeta), así no hay dos formas distintas de mover un
/// documento en la app.
struct FolderMoveMenu: View {
    let document: ScanDocument

    @Environment(ScanCoordinator.self) private var coordinator
    @Query(sort: \ScanFolder.sortIndex) private var folders: [ScanFolder]

    var body: some View {
        Menu {
            Button {
                Task { await coordinator.moveDocument(document.id, toFolder: nil) }
            } label: {
                folderRow(name: String(localized: "folder.none", defaultValue: "Ninguna"), isCurrent: document.folder == nil)
            }

            if !folders.isEmpty {
                Divider()
                ForEach(folders) { folder in
                    Button {
                        Task { await coordinator.moveDocument(document.id, toFolder: folder.id) }
                    } label: {
                        folderRow(name: folder.name, isCurrent: document.folder?.id == folder.id)
                    }
                }
            }
        } label: {
            Label(String(localized: "document.moveToFolder", defaultValue: "Mover a carpeta"), systemImage: "folder")
        }
    }

    @ViewBuilder
    private func folderRow(name: String, isCurrent: Bool) -> some View {
        if isCurrent {
            Label(name, systemImage: "checkmark")
        } else {
            Text(name)
        }
    }
}
