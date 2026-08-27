import SwiftData
import SwiftUI

struct SearchView: View {
    @Query(filter: #Predicate<ScanDocument> { $0.deletedAt == nil })
    private var documents: [ScanDocument]

    @Environment(\.colorScheme) private var scheme
    @State private var query = ""

    private var results: [DocumentSearch.Result] {
        DocumentSearch.results(for: query, in: documents)
    }

    var body: some View {
        Group {
            if query.isEmpty {
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
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { result in
                    NavigationLink(value: result.documentID) {
                        SearchResultRow(result: result, query: query)
                    }
                    .listRowBackground(DS.ColorToken.card(scheme))
                    .listRowSeparatorTint(DS.ColorToken.border(scheme))
                }
                .listStyle(.plain)
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "search.title", defaultValue: "Buscar"))
        .searchable(
            text: $query,
            prompt: Text(String(localized: "library.searchPrompt", defaultValue: "Buscar texto en documentos"))
        )
        .navigationDestination(for: UUID.self) { DocumentDetailView(documentID: $0) }
    }
}

private struct SearchResultRow: View {
    let result: DocumentSearch.Result
    let query: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x1) {
            Text(highlighted(result.title))
                .font(DS.Typography.rowTitle)
            if let snippet = result.snippet {
                Text(highlighted(snippet))
                    .font(DS.Typography.captionText)
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, DS.Spacing.x1)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: [.caseInsensitive]) {
            attributed[range].foregroundColor = DS.ColorToken.primary(scheme)
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}

#Preview {
    NavigationStack { SearchView() }
}
