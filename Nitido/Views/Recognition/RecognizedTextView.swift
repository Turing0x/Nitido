import SwiftData
import SwiftUI
import UIKit

/// Texto reconocido de una página, con copiar y exportar a `.txt`.
struct RecognizedTextView: View {
    let documentID: UUID
    let pageID: UUID

    @Environment(\.colorScheme) private var scheme
    @Query private var pages: [ScanPage]
    @Query private var documents: [ScanDocument]

    @State private var exportURL: URL?

    init(documentID: UUID, pageID: UUID) {
        self.documentID = documentID
        self.pageID = pageID
        _pages = Query(filter: #Predicate<ScanPage> { $0.id == pageID })
        _documents = Query(filter: #Predicate<ScanDocument> { $0.id == documentID })
    }

    private var page: ScanPage? { pages.first }
    private var document: ScanDocument? { documents.first }

    var body: some View {
        Group {
            if let page, !page.ocrText.isEmpty {
                ScrollView {
                    Text(page.ocrText)
                        .textSelection(.enabled)
                        .font(DS.Typography.bodyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Spacing.screenGutter)
                }
            } else if page?.ocrDeferred == true {
                // Se distingue del vacío genérico a propósito: aquí no es que
                // no haya texto, es que todavía no se ha mirado.
                ContentUnavailableView(
                    String(localized: "recognizedText.deferred.title", defaultValue: "Esperando al mes que viene"),
                    systemImage: "clock.badge.questionmark",
                    description: Text(String(
                        localized: "recognizedText.deferred.description",
                        defaultValue: "Se han agotado las páginas que el plan gratuito reconoce cada mes. Esta se reconocerá sola cuando empiece el siguiente, o al momento si te haces Pro."
                    ))
                )
            } else {
                ContentUnavailableView(
                    String(localized: "recognizedText.empty.title", defaultValue: "Sin texto reconocido"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(String(
                        localized: "recognizedText.empty.description",
                        defaultValue: "Esta página todavía no tiene texto reconocido."
                    ))
                )
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "recognizedText.title", defaultValue: "Texto reconocido"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onChange(of: page?.ocrText) { _, _ in Task { await prepareExport() } }
        .task { await prepareExport() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: DS.Spacing.x3) {
                Button {
                    UIPasteboard.general.string = page?.ocrText
                } label: {
                    Label(String(localized: "recognizedText.copy", defaultValue: "Copiar"), systemImage: "doc.on.doc")
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label(String(localized: "recognizedText.export", defaultValue: "Exportar"), systemImage: "square.and.arrow.up")
                    }
                }
            }
            .disabled(page?.ocrText.isEmpty != false)
        }
    }

    /// Escribe el texto a un fichero temporal para que `ShareLink` pueda
    /// compartirlo como `.txt`, no como texto plano suelto.
    private func prepareExport() async {
        guard let page, !page.ocrText.isEmpty else {
            exportURL = nil
            return
        }
        // Los valores se copian fuera del modelo antes de salir del actor:
        // `ScanPage` es de SwiftData y no puede cruzar la frontera.
        let text = page.ocrText
        let sanitized = ImageExporter.sanitize(document?.title ?? "")
        let fileName = "\(sanitized)-p\(page.index + 1).txt"

        exportURL = await Task.detached(priority: .utility) { () -> URL? in
            let url = URL.temporaryDirectory.appending(path: fileName, directoryHint: .notDirectory)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }.value
    }
}
