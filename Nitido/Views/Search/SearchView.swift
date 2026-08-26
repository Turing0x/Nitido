import SwiftUI

struct SearchView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "search.empty.title", defaultValue: "Buscar"),
                systemImage: "magnifyingglass"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(String(localized: "search.empty.description", defaultValue: "Busca por título o por texto reconocido."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "search.title", defaultValue: "Buscar"))
    }
}

#Preview {
    NavigationStack { SearchView() }
}
