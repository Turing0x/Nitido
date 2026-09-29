import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.fileStore) private var fileStore
    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(StoreManager.self) private var storeManager
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.colorScheme) private var scheme
    @Query(filter: #Predicate<ScanDocument> { $0.deletedAt != nil }) private var trashedDocuments: [ScanDocument]

    @State private var sizeOnDisk: Int64?
    @State private var isRegeneratingThumbnails = false
    @State private var regeneratedCount: Int?
    @State private var isShowingPaywall = false
    @State private var requestedFeature: ProFeature?
    @State private var deferredPageCount = 0

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
            proSection

            Section {
                Picker(
                    selection: $ocrLanguageRaw
                ) {
                    ForEach(OCRLanguagePreference.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                } label: {
                    ProRowLabel(
                        title: String(localized: "settings.ocrLanguage", defaultValue: "Idioma del OCR"),
                        isAllowed: entitlements.allows(.manualOCRLanguage)
                    )
                }
                .proGated(.manualOCRLanguage, isAllowed: entitlements.allows(.manualOCRLanguage)) {
                    requestedFeature = $0
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

                if let privacy = LegalLinks.privacyPolicy {
                    Link(String(localized: "paywall.privacy", defaultValue: "Política de privacidad"), destination: privacy)
                        .font(DS.Typography.bodyText)
                        .listRowBackground(DS.ColorToken.card(scheme))
                }
                if let terms = LegalLinks.termsOfUse {
                    Link(String(localized: "paywall.terms", defaultValue: "Términos de uso"), destination: terms)
                        .font(DS.Typography.bodyText)
                        .listRowBackground(DS.ColorToken.card(scheme))
                }

                Text(String(
                    localized: "settings.privacy.claim",
                    defaultValue: "Tus documentos no salen de este dispositivo: todo el procesado ocurre aquí y Nítido no los envía a ninguna parte. La única conexión que existe es la que hace el sistema con App Store cuando compras."
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
        .proFeatureNotice($requestedFeature)
        .sheet(isPresented: $isShowingPaywall) {
            NavigationStack { PaywallView() }
        }
        .alert(
            String(localized: "purchase.error.title", defaultValue: "No se pudo completar"),
            isPresented: Binding(
                get: { storeManager.errorMessage != nil },
                set: { if !$0 { storeManager.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {}
        } message: {
            Text(storeManager.errorMessage ?? "")
        }
        .task {
            sizeOnDisk = await Self.measureSizeOnDisk(fileStore)
        }
        .task {
            // El periodo puede haber cambiado con la app abierta desde el mes
            // pasado; sin esto el contador se vería rancio.
            entitlements.refreshPeriod()
            deferredPageCount = await coordinator.deferredOCRPageCount()
        }
    }

    // MARK: - Nítido Pro

    @ViewBuilder
    private var proSection: some View {
        Section {
            Button {
                isShowingPaywall = true
            } label: {
                LabeledContent(String(localized: "settings.pro", defaultValue: "Nítido Pro")) {
                    Text(entitlements.isPro
                         ? String(localized: "settings.pro.active", defaultValue: "Activo")
                         : String(localized: "settings.pro.see", defaultValue: "Ver planes"))
                }
            }
            .font(DS.Typography.bodyText)
            .listRowBackground(DS.ColorToken.card(scheme))

            if !entitlements.isPro {
                LabeledContent(
                    String(localized: "settings.pro.monthlyOCR", defaultValue: "Páginas reconocidas este mes")
                ) {
                    Text(String(
                        localized: "settings.pro.monthlyOCR.count",
                        defaultValue: "\(entitlements.quota.used) de \(OCRQuota.freeMonthlyAllowance)"
                    ))
                }
                .font(DS.Typography.bodyText)
                .listRowBackground(DS.ColorToken.card(scheme))

                if deferredPageCount > 0 {
                    Text(String(
                        localized: "settings.pro.deferred",
                        defaultValue: "Hay \(deferredPageCount) páginas esperando a que empiece el mes que viene. Se reconocerán solas, o al momento si te haces Pro."
                    ))
                    .font(DS.Typography.captionText)
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                    .listRowBackground(DS.ColorToken.card(scheme))
                }
            }

            Button {
                Task { await storeManager.restorePurchases() }
            } label: {
                HStack {
                    Text(String(localized: "paywall.restore", defaultValue: "Restaurar compras"))
                    Spacer()
                    if storeManager.phase == .restoring {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .font(DS.Typography.bodyText)
            .disabled(storeManager.phase.isWorking)
            .listRowBackground(DS.ColorToken.card(scheme))
        } header: {
            Text(String(localized: "settings.subscription", defaultValue: "Suscripción"))
                .dsEyebrow()
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
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

private struct SettingsPreview: View {
    @State private var storeManager = StoreManager()

    var body: some View {
        NavigationStack { SettingsView() }
            .environment(storeManager)
            .environment(Entitlements(storeManager: storeManager))
    }
}

#Preview {
    SettingsPreview()
}
