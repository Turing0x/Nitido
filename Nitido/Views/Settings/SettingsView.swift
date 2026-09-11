import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.fileStore) private var fileStore
    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.colorScheme) private var scheme
    @Query(filter: #Predicate<ScanDocument> { $0.deletedAt != nil }) private var trashedDocuments: [ScanDocument]

    @State private var sizeOnDisk: Int64?
    @State private var isRegeneratingThumbnails = false
    @State private var regeneratedCount: Int?

    @AppStorage("settings.ocrLanguage") private var ocrLanguageRaw = OCRLanguagePreference.automatic.rawValue
    @AppStorage("settings.defaultFilter") private var defaultFilterRaw = PageFilter.original.rawValue
    @AppStorage("settings.exportCompression") private var exportCompressionRaw = PDFCompressionLevel.high.rawValue

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                Picker(
                    String(localized: "settings.ocrLanguage", defaultValue: "Idioma del OCR"),
                    selection: $ocrLanguageRaw
                ) {
                    ForEach(OCRLanguagePreference.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .listRowBackground(DS.ColorToken.card(scheme))

                Picker(
                    String(localized: "settings.defaultFilter", defaultValue: "Filtro por defecto"),
                    selection: $defaultFilterRaw
                ) {
                    ForEach(PageFilter.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .listRowBackground(DS.ColorToken.card(scheme))

                Picker(
                    String(localized: "settings.exportQuality", defaultValue: "Calidad de exportación"),
                    selection: $exportCompressionRaw
                ) {
                    Text(String(localized: "export.compression.high", defaultValue: "Alta")).tag(PDFCompressionLevel.high.rawValue)
                    Text(String(localized: "export.compression.medium", defaultValue: "Media")).tag(PDFCompressionLevel.medium.rawValue)
                    Text(String(localized: "export.compression.low", defaultValue: "Baja")).tag(PDFCompressionLevel.low.rawValue)
                }
                .listRowBackground(DS.ColorToken.card(scheme))
            } header: {
                Text(String(localized: "settings.scanning", defaultValue: "Escaneo y exportación"))
                    .dsEyebrow()
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }

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

                regenerateThumbnailsRow
                    .listRowBackground(DS.ColorToken.card(scheme))

                NavigationLink {
                    TrashView()
                } label: {
                    LabeledContent(
                        String(localized: "settings.trash", defaultValue: "Papelera"),
                        value: trashedDocuments.isEmpty ? "" : "\(trashedDocuments.count)"
                    )
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
            sizeOnDisk = await Self.measureSizeOnDisk(fileStore)
        }
    }

    /// `sizeOnDisk()` enumera **todo** el árbol de ficheros de la app pidiendo
    /// los atributos de cada uno. En el `MainActor` —que es donde corre `.task`
    /// de una vista— eso congela Ajustes en una biblioteca grande.
    private static func measureSizeOnDisk(_ fileStore: any FileStoring) async -> Int64? {
        await Task.detached(priority: .utility) {
            try? fileStore.sizeOnDisk()
        }.value
    }

    @ViewBuilder
    private var regenerateThumbnailsRow: some View {
        Button {
            Task {
                isRegeneratingThumbnails = true
                regeneratedCount = await coordinator.regenerateThumbnails()
                sizeOnDisk = await Self.measureSizeOnDisk(fileStore)
                isRegeneratingThumbnails = false
            }
        } label: {
            HStack {
                Text(String(localized: "settings.regenerateThumbnails", defaultValue: "Regenerar miniaturas"))
                Spacer()
                if isRegeneratingThumbnails {
                    ProgressView().controlSize(.small)
                } else if let regeneratedCount {
                    Text(String(localized: "settings.regenerateThumbnails.done", defaultValue: "\(regeneratedCount) hechas"))
                        .font(DS.Typography.captionText)
                        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                }
            }
        }
        .disabled(isRegeneratingThumbnails)
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
