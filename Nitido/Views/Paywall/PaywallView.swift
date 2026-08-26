import SwiftUI

struct PaywallView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "paywall.empty.title", defaultValue: "Nítido Pro"),
                systemImage: "sparkles"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            Text(String(localized: "paywall.empty.description", defaultValue: "El paywall se implementa en la Sprint 6."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "paywall.title", defaultValue: "Nítido Pro"))
    }
}

#Preview {
    NavigationStack { PaywallView() }
}
