import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Menú de orígenes: cámara, Fotos y Archivos.
///
/// La cámara solo aparece si el dispositivo la soporta. En el simulador
/// `VNDocumentCameraViewController.isSupported` es `false`, y en ese caso se
/// enseña el camino alternativo en lugar de un botón que no hace nada.
struct ScanSourceMenu<Label: View>: View {
    @Binding var isShowingCamera: Bool
    @Binding var isShowingPhotoPicker: Bool
    @Binding var isShowingFileImporter: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            if DocumentCameraView.isSupported {
                Button {
                    isShowingCamera = true
                } label: {
                    SwiftUI.Label(
                        String(localized: "scan.source.camera", defaultValue: "Escanear con la cámara"),
                        systemImage: "camera"
                    )
                }
            }
            Button {
                isShowingPhotoPicker = true
            } label: {
                SwiftUI.Label(
                    String(localized: "scan.source.photos", defaultValue: "Importar de Fotos"),
                    systemImage: "photo.on.rectangle"
                )
            }
            Button {
                isShowingFileImporter = true
            } label: {
                SwiftUI.Label(
                    String(localized: "scan.source.files", defaultValue: "Importar de Archivos"),
                    systemImage: "folder"
                )
            }
        } label: {
            label()
        }
    }
}

private struct ScanSourcesModifier: ViewModifier {
    @Binding var isShowingCamera: Bool
    @Binding var isShowingPhotoPicker: Bool
    @Binding var isShowingFileImporter: Bool
    @Binding var photoItems: [PhotosPickerItem]
    /// `nil` crea un documento nuevo; con identificador, añade páginas a ese.
    let destinationDocumentID: UUID?

    @Environment(ScanCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isShowingCamera) {
                DocumentCameraView(
                    onFinish: { images in
                        isShowingCamera = false
                        Task { await deliver(images) }
                    },
                    onCancel: { isShowingCamera = false },
                    onError: { error in
                        isShowingCamera = false
                        coordinator.reportCameraError(error)
                    }
                )
                .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $isShowingPhotoPicker,
                selection: $photoItems,
                matching: .images
            )
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: true
            ) { result in
                Task { await coordinator.importFromFiles(result: result, into: destinationDocumentID) }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await coordinator.importFromPhotos(items, into: destinationDocumentID)
                    photoItems = []
                }
            }
    }

    private func deliver(_ images: [SendableImage]) async {
        if let destinationDocumentID {
            await coordinator.addPages(images, to: destinationDocumentID)
        } else {
            await coordinator.createDocument(from: images)
        }
    }
}

extension View {
    /// Engancha cámara, Fotos y Archivos a una pantalla.
    func scanSources(
        isShowingCamera: Binding<Bool>,
        isShowingPhotoPicker: Binding<Bool>,
        isShowingFileImporter: Binding<Bool>,
        photoItems: Binding<[PhotosPickerItem]>,
        destinationDocumentID: UUID?
    ) -> some View {
        modifier(ScanSourcesModifier(
            isShowingCamera: isShowingCamera,
            isShowingPhotoPicker: isShowingPhotoPicker,
            isShowingFileImporter: isShowingFileImporter,
            photoItems: photoItems,
            destinationDocumentID: destinationDocumentID
        ))
    }

    /// Alerta de error del coordinador. Ningún fallo se traga en silencio.
    func errorAlert(coordinator: ScanCoordinator) -> some View {
        alert(
            String(localized: "error.title", defaultValue: "Algo ha fallado"),
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { if !$0 { coordinator.errorMessage = nil } }
            ),
            actions: {
                Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {}
            },
            message: { Text(coordinator.errorMessage ?? "") }
        )
    }
}

/// Indicador de progreso mientras se escriben las páginas en disco.
struct ProcessingOverlay: View {
    let done: Int
    let total: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: DS.Spacing.x3) {
            ProgressView()
            Text(String(
                localized: "scan.processing",
                defaultValue: "Procesando \(done) de \(total)"
            ))
            .font(DS.Typography.calloutText)
            .foregroundStyle(DS.ColorToken.foreground(scheme))
        }
        .padding(DS.Spacing.x6)
        .background(DS.ColorToken.card(scheme))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .dsShadow(.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Overlay.scrim.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}
