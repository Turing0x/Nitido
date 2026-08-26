import SwiftUI

struct ExportView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "export.empty.title", defaultValue: "Exportar"),
                systemImage: "square.and.arrow.up"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(String(localized: "export.empty.description", defaultValue: "Las opciones de exportación llegan en la Sprint 4."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "export.title", defaultValue: "Exportar"))
    }
}

#Preview {
    NavigationStack { ExportView() }
}
