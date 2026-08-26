import SwiftUI

struct SettingsView: View {
    @Environment(\.fileStore) private var fileStore
    @Environment(\.colorScheme) private var scheme
    @State private var sizeOnDisk: Int64?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "settings.storage.used", defaultValue: "Espacio ocupado")
                ) {
                    if let sizeOnDisk {
                        Text(sizeOnDisk, format: .byteCount(style: .file))
                    } else {
                        Text(verbatim: "—")
                    }
                }
                .font(DS.Typography.bodyText)
                .listRowBackground(DS.ColorToken.card(scheme))
            } header: {
                Text(String(localized: "settings.storage", defaultValue: "Almacenamiento"))
                    .dsEyebrow()
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }

            Section {
                LabeledContent(
                    String(localized: "settings.version", defaultValue: "Versión"),
                    value: version
                )
                .font(DS.Typography.bodyText)
                .listRowBackground(DS.ColorToken.card(scheme))

                Text(String(
                    localized: "settings.privacy.claim",
                    defaultValue: "Nítido no usa la red. Todo el procesado ocurre en este dispositivo."
                ))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                .listRowBackground(DS.ColorToken.card(scheme))
            } header: {
                Text(String(localized: "settings.about", defaultValue: "Acerca de"))
                    .dsEyebrow()
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }
        }
        .listStyle(.insetGrouped)
        .dsScreenBackground()
        .navigationTitle(String(localized: "settings.title", defaultValue: "Ajustes"))
        .task {
            sizeOnDisk = try? fileStore.sizeOnDisk()
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
