import SwiftUI

struct FoldersView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
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
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "folders.title", defaultValue: "Carpetas"))
    }
}

#Preview {
    NavigationStack { FoldersView() }
}
