import SwiftUI

/// Opciones de exportación de un documento: PDF con capa de texto invisible
/// buscable, o páginas sueltas en JPG/PNG. Pantalla parametrizada por
/// `documentID`, mismo patrón que `RecognizedTextView`/`DocumentDetailView`.
///
/// A diferencia de esas vistas, no usa `@Query`: todo lo que necesita
/// (título, nombres de fichero, cajas de OCR) llega en un único viaje al
/// actor a través de `coordinator.exportInfo(for:)`.
struct ExportView: View {
    let documentID: UUID

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.fileStore) private var fileStore
    @Environment(\.colorScheme) private var scheme

    private enum Format: String, CaseIterable, Identifiable {
        case pdf, jpg, png
        var id: String { rawValue }

        var label: String {
            switch self {
            case .pdf: String(localized: "export.format.pdf", defaultValue: "PDF")
            case .jpg: String(localized: "export.format.jpg", defaultValue: "JPG")
            case .png: String(localized: "export.format.png", defaultValue: "PNG")
            }
        }
    }

    private enum PageSelectionMode: String, CaseIterable, Identifiable {
        case all, single
        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: String(localized: "export.pageSelection.all", defaultValue: "Todas")
            case .single: String(localized: "export.pageSelection.single", defaultValue: "Página suelta")
            }
        }
    }

    @State private var format: Format = .pdf
    @State private var pageSizeMode: PDFPageSizeMode = .fitToImage
    @State private var compressionLevel: PDFCompressionLevel = .high
    @State private var pageSelectionMode: PageSelectionMode = .all
    @State private var selectedPageID: UUID?
    @State private var isPasswordProtected = false
    @State private var password = ""

    @State private var exportInfo: DocumentExportInfo?
    @State private var loadError: String?
    @State private var estimatedSize: Int64?
    @State private var isEstimating = false
    @State private var exportURLs: [URL] = []
    @State private var isExporting = false
    @State private var exportError: String?

    init(documentID: UUID) {
        self.documentID = documentID
        let stored = UserDefaults.standard.string(forKey: "settings.exportCompression")
            .flatMap(PDFCompressionLevel.init(rawValue:)) ?? .high
        _compressionLevel = State(initialValue: stored)
    }

    var body: some View {
        Group {
            if let exportInfo {
                form(for: exportInfo)
            } else if let loadError {
                ContentUnavailableView(
                    String(localized: "export.error.title", defaultValue: "No se pudo exportar"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "export.title", defaultValue: "Exportar"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExportInfo() }
        .task(id: estimationKey) { await recomputeEstimatedSize() }
        .onChange(of: optionsSignature) {
            // Cualquier cambio en las opciones invalida el fichero ya
            // exportado: si no se limpia, `ShareLink` seguiría ofreciendo el
            // PDF/JPG generado con los ajustes anteriores como si fuera el
            // resultado de los nuevos.
            exportURLs = []
            exportError = nil
        }
    }

    /// Clave de recálculo del peso estimado: el tamaño de página no lo afecta
    /// (la geometría no cambia el nivel de compresión de la imagen), así que
    /// no forma parte de la clave.
    private var estimationKey: String {
        "\(format.rawValue)-\(compressionLevel.rawValue)-\(pageSelectionMode.rawValue)-\(selectedPageID?.uuidString ?? "")-\(exportInfo != nil)"
    }

    /// Firma de todas las opciones que cambian el fichero exportado.
    private var optionsSignature: String {
        "\(format.rawValue)-\(pageSizeMode.rawValue)-\(compressionLevel.rawValue)-\(pageSelectionMode.rawValue)-\(selectedPageID?.uuidString ?? "")-\(isPasswordProtected)-\(password)"
    }

    @ViewBuilder
    private func form(for info: DocumentExportInfo) -> some View {
        List {
            Section {
                Picker(String(localized: "export.format.title", defaultValue: "Formato"), selection: $format) {
                    ForEach(Format.allCases) { format in
                        Text(format.label).tag(format)
                    }
                }
                .listRowBackground(DS.ColorToken.card(scheme))
            }

            if format == .pdf {
                Section {
                    Picker(String(localized: "export.pageSize.title", defaultValue: "Tamaño de página"), selection: $pageSizeMode) {
                        Text(String(localized: "export.pageSize.fitToImage", defaultValue: "Ajustar a la imagen")).tag(PDFPageSizeMode.fitToImage)
                        Text(String(localized: "export.pageSize.a4", defaultValue: "A4")).tag(PDFPageSizeMode.a4)
                        Text(String(localized: "export.pageSize.letter", defaultValue: "Carta")).tag(PDFPageSizeMode.letter)
                    }
                    .listRowBackground(DS.ColorToken.card(scheme))
                } header: {
                    Text(String(localized: "export.pageSize.title", defaultValue: "Tamaño de página"))
                        .dsEyebrow()
                        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                }
            } else if info.pages.count > 1 {
                Section {
                    Picker(String(localized: "export.pageSelection.title", defaultValue: "Páginas"), selection: $pageSelectionMode) {
                        ForEach(PageSelectionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(DS.ColorToken.card(scheme))

                    if pageSelectionMode == .single {
                        Picker(String(localized: "export.pageSelection.title", defaultValue: "Páginas"), selection: $selectedPageID) {
                            ForEach(info.pages, id: \.pageID) { page in
                                Text(String(localized: "document.page", defaultValue: "Página \(page.index + 1)"))
                                    .tag(Optional(page.pageID))
                            }
                        }
                        .listRowBackground(DS.ColorToken.card(scheme))
                    }
                } header: {
                    Text(String(localized: "export.pageSelection.title", defaultValue: "Páginas"))
                        .dsEyebrow()
                        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                }
            }

            Section {
                Picker(String(localized: "export.compression.title", defaultValue: "Compresión"), selection: $compressionLevel) {
                    Text(String(localized: "export.compression.high", defaultValue: "Alta")).tag(PDFCompressionLevel.high)
                    Text(String(localized: "export.compression.medium", defaultValue: "Media")).tag(PDFCompressionLevel.medium)
                    Text(String(localized: "export.compression.low", defaultValue: "Baja")).tag(PDFCompressionLevel.low)
                }
                .listRowBackground(DS.ColorToken.card(scheme))

                estimatedSizeRow
                    .listRowBackground(DS.ColorToken.card(scheme))
            } header: {
                Text(String(localized: "export.compression.title", defaultValue: "Compresión"))
                    .dsEyebrow()
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }

            if format == .pdf {
                Section {
                    Toggle(
                        String(localized: "export.password.toggle", defaultValue: "Proteger con contraseña"),
                        isOn: $isPasswordProtected
                    )
                    .listRowBackground(DS.ColorToken.card(scheme))

                    if isPasswordProtected {
                        SecureField(
                            String(localized: "export.password.field", defaultValue: "Contraseña"),
                            text: $password
                        )
                        .listRowBackground(DS.ColorToken.card(scheme))

                        if password.isEmpty {
                            Text(String(
                                localized: "export.password.required",
                                defaultValue: "Escribe una contraseña para poder exportar el PDF protegido."
                            ))
                            .font(DS.Typography.captionText)
                            .foregroundStyle(DS.ColorToken.destructive(scheme))
                            .listRowBackground(DS.ColorToken.card(scheme))
                        }
                    }
                }
            }

            Section {
                exportButton(for: info)
                    .listRowBackground(DS.ColorToken.card(scheme))

                if let exportError {
                    Text(exportError)
                        .font(DS.Typography.calloutText)
                        .foregroundStyle(DS.ColorToken.destructive(scheme))
                        .listRowBackground(DS.ColorToken.card(scheme))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var estimatedSizeRow: some View {
        if isEstimating {
            LabeledContent(String(localized: "export.compression.title", defaultValue: "Compresión")) {
                Text(String(localized: "export.compression.estimating", defaultValue: "Calculando…"))
            }
            .font(DS.Typography.captionText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        } else if let estimatedSize {
            Text(String(
                localized: "export.compression.estimatedSize",
                defaultValue: "Peso estimado: \(Self.byteFormatter.string(fromByteCount: estimatedSize))"
            ))
            .font(DS.Typography.captionText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
    }

    @ViewBuilder
    private func exportButton(for info: DocumentExportInfo) -> some View {
        if !exportURLs.isEmpty {
            ShareLink(items: exportURLs) {
                Label(String(localized: "export.action", defaultValue: "Exportar"), systemImage: "square.and.arrow.up")
            }
        } else if isExporting {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else {
            Button {
                Task { await performExport(for: info) }
            } label: {
                Label(String(localized: "export.action", defaultValue: "Exportar"), systemImage: "square.and.arrow.up")
            }
            .disabled(isExportDisabled)
        }
    }

    /// Una página suelta sin elegir no se puede exportar, y una protección
    /// con contraseña activada pero en blanco tampoco: antes exportaba un PDF
    /// sin cifrar que el usuario creía protegido.
    private var isExportDisabled: Bool {
        if format != .pdf && pageSelectionMode == .single && selectedPageID == nil { return true }
        if format == .pdf && isPasswordProtected && password.isEmpty { return true }
        return false
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    // MARK: - Carga y cálculo

    private func loadExportInfo() async {
        do {
            let info = try await coordinator.exportInfo(for: documentID)
            exportInfo = info
            if selectedPageID == nil {
                selectedPageID = info.pages.first?.pageID
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func recomputeEstimatedSize() async {
        guard let exportInfo else { return }
        isEstimating = true
        let level = compressionLevel
        let store = fileStore
        let relevantPages: [PageExportInfo]
        switch (format, pageSelectionMode) {
        case (.pdf, _), (_, .all):
            relevantPages = exportInfo.pages
        case (_, .single):
            relevantPages = exportInfo.pages.filter { $0.pageID == selectedPageID }
        }
        let scoped = DocumentExportInfo(documentID: exportInfo.documentID, title: exportInfo.title, pages: relevantPages)
        let isPDF = format == .pdf

        let size = try? await Task.detached(priority: .utility) {
            if isPDF {
                return try PDFSizeEstimator.estimatedFileSize(
                    for: scoped,
                    level: level,
                    fileStore: store,
                    documentID: scoped.documentID
                )
            }
            // JPG/PNG sueltos no llevan la estructura de un PDF encima: el
            // peso es directamente la suma de los ficheros de imagen.
            var total: Int64 = 0
            for page in scoped.pages {
                let data = try store.read(fileName: page.processedFileName, documentID: scoped.documentID)
                total += Int64(try PDFCompression.compressedJPEGData(from: data, level: level).count)
            }
            return total
        }.value

        if !Task.isCancelled {
            estimatedSize = size
            isEstimating = false
        }
    }

    // MARK: - Exportación

    private func performExport(for info: DocumentExportInfo) async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }

        let store = fileStore
        do {
            switch format {
            case .pdf:
                let options = PDFExportOptions(pageSizeMode: pageSizeMode, compressionLevel: compressionLevel)
                // `nil` = no se pidió protección. Nunca "" — ver
                // `PDFPasswordProtector.protect`.
                let protectionPassword: String? = isPasswordProtected ? password : nil
                let fileName = "\(ImageExporter.sanitize(info.title)).pdf"
                // La escritura va dentro de la misma tarea que genera los bytes:
                // un PDF de decenas de megabytes escrito desde el `MainActor`
                // bloquea la interfaz el tiempo que tarde el disco.
                let url = try await Task.detached(priority: .userInitiated) { () -> URL in
                    let raw = try PDFExporter.export(info, options: options, fileStore: store)
                    let data = try PDFPasswordProtector.protect(raw, password: protectionPassword)
                    let url = URL.temporaryDirectory.appending(path: fileName, directoryHint: .notDirectory)
                    try data.write(to: url, options: .atomic)
                    return url
                }.value
                exportURLs = [url]

            case .jpg, .png:
                let imageFormat: ImageExportFormat = format == .jpg ? .jpg : .png
                let selection: ImagePageSelection = pageSelectionMode == .all
                    ? .all
                    : .single(pageID: selectedPageID ?? info.pages.first?.pageID ?? UUID())
                let level = compressionLevel
                exportURLs = try await Task.detached(priority: .userInitiated) {
                    try ImageExporter.exportURLs(
                        for: info,
                        selection: selection,
                        format: imageFormat,
                        compressionLevel: level,
                        fileStore: store
                    )
                }.value
            }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { ExportView(documentID: UUID()) }
}
