import SwiftData
import SwiftUI

/// Papelera: documentos con `deletedAt` puesto. Restaurar los saca de aquí;
/// "eliminar definitivamente" borra registro y ficheros sin esperar a los
/// 30 días de purga automática (`ScanCoordinator.purgeExpiredTrash`).
struct TrashView: View {
    @Query(
        filter: #Predicate<ScanDocument> { $0.deletedAt != nil },
        sort: \ScanDocument.deletedAt,
        order: .reverse
    )
    private var documents: [ScanDocument]

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme
    @State private var documentPendingPermanentDelete: ScanDocument?

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    String(localized: "trash.empty.title", defaultValue: "La papelera está vacía"),
                    systemImage: "trash",
                    description: Text(String(
                        localized: "trash.empty.description",
                        defaultValue: "Los documentos que muevas a la papelera aparecen aquí durante 30 días."
                    ))
                )
            } else {
                List(documents) { document in
                    HStack(spacing: DS.Spacing.x3) {
                        VStack(alignment: .leading, spacing: DS.Spacing.x1) {
                            Text(document.title)
                                .font(DS.Typography.bodyText)
                            if let deletedAt = document.deletedAt {
                                Text(String(
                                    localized: "trash.deletedAt",
                                    defaultValue: "Eliminado el \(deletedAt.formatted(date: .abbreviated, time: .omitted))"
                                ))
                                .font(DS.Typography.captionText)
                                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                            }
                        }
                        Spacer()
                        Button {
                            Task { await coordinator.restoreFromTrash(document.id) }
                        } label: {
                            Label(String(localized: "trash.restore", defaultValue: "Restaurar"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }
                    .listRowBackground(DS.ColorToken.card(scheme))
                    .listRowSeparatorTint(DS.ColorToken.border(scheme))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            documentPendingPermanentDelete = document
                        } label: {
                            Label(String(localized: "trash.deleteForever", defaultValue: "Eliminar definitivamente"), systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "trash.title", defaultValue: "Papelera"))
        .confirmationDialog(
            String(localized: "trash.deleteForever.title", defaultValue: "¿Eliminar definitivamente?"),
            isPresented: Binding(
                get: { documentPendingPermanentDelete != nil },
                set: { if !$0 { documentPendingPermanentDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "trash.deleteForever", defaultValue: "Eliminar definitivamente"), role: .destructive) {
                guard let document = documentPendingPermanentDelete else { return }
                Task { await coordinator.permanentlyDelete(document.id) }
                documentPendingPermanentDelete = nil
            }
            Button(String(localized: "common.cancel", defaultValue: "Cancelar"), role: .cancel) {
                documentPendingPermanentDelete = nil
            }
        } message: {
            Text(String(
                localized: "trash.deleteForever.message",
                defaultValue: "Esta acción no se puede deshacer: el documento y sus páginas se borran del todo."
            ))
        }
        .errorAlert(coordinator: coordinator)
    }
}

#Preview {
    NavigationStack { TrashView() }
}
