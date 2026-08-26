import SwiftUI
import VisionKit

/// Envoltorio de `VNDocumentCameraViewController`.
///
/// VisionKit ya trae detección de bordes, corrección de perspectiva, disparo
/// automático y captura de varias páginas seguidas. No se reimplementa nada de
/// eso ni se personaliza la interfaz: la cámara es la de Apple.
struct DocumentCameraView: UIViewControllerRepresentable {

    /// `true` cuando el dispositivo puede abrir la cámara de documentos.
    /// En el simulador es `false`, así que hay que ofrecer otro camino
    /// (importar desde Fotos) en lugar de un botón que no hace nada.
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    let onFinish: ([SendableImage]) -> Void
    let onCancel: () -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel, onError: onError)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([SendableImage]) -> Void
        private let onCancel: () -> Void
        private let onError: (Error) -> Void

        init(
            onFinish: @escaping ([SendableImage]) -> Void,
            onCancel: @escaping () -> Void,
            onError: @escaping (Error) -> Void
        ) {
            self.onFinish = onFinish
            self.onCancel = onCancel
            self.onError = onError
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [SendableImage] = []
            images.reserveCapacity(scan.pageCount)

            for index in 0..<scan.pageCount {
                // Cada página en su propio pool: aquí hay varios megapíxeles por
                // página y la tanda puede ser larga.
                autoreleasepool {
                    let page = scan.imageOfPage(at: index)
                    guard let cgImage = page.cgImage else { return }
                    images.append(
                        SendableImage(cgImage, orientation: page.imageOrientation.cgOrientation)
                    )
                }
            }

            onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            onError(error)
        }
    }
}

extension UIImage.Orientation {
    /// Equivalencia entre la orientación de UIKit y la EXIF que entiende
    /// Core Graphics. Los nombres coinciden uno a uno, pero los valores brutos
    /// **no**: `UIImage.Orientation.left` vale 2 y `CGImagePropertyOrientation.left`
    /// vale 8. Hay que traducir por nombre, nunca por `rawValue`.
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
