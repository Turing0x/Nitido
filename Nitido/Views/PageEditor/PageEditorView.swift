import SwiftUI

struct PageEditorView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "pageEditor.empty.title", defaultValue: "Editar página"),
                systemImage: "crop"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(String(localized: "pageEditor.empty.description", defaultValue: "Recorte, filtros y rotación llegan en la Sprint 2."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "pageEditor.title", defaultValue: "Editar página"))
    }
}

#Preview {
    NavigationStack { PageEditorView() }
}
