import CoreGraphics
import Vision

/// Detecta una hoja importada sin modificar la imagen. Vision trabaja con el
/// origen abajo a la izquierda; la app persiste y presenta los puntos con el
/// origen arriba a la izquierda, así que el cambio de Y se hace aquí.
enum DocumentQuadDetector {
    static func detect(in image: CGImage) async -> QuadPoints? {
        do {
            let request = DetectDocumentSegmentationRequest()
            let handler = ImageRequestHandler(image)
            guard let observation = try await handler.perform(request) else { return nil }

            let quad = QuadPoints(
                topLeft: point(from: observation.topLeft),
                topRight: point(from: observation.topRight),
                bottomRight: point(from: observation.bottomRight),
                bottomLeft: point(from: observation.bottomLeft)
            )
            return isUsable(quad) ? quad : nil
        } catch {
            // La detección es una ayuda; una imagen normal siempre debe poder
            // entrar aunque Vision no encuentre un documento.
            return nil
        }
    }

    private static func point(from point: NormalizedPoint) -> QuadPoints.Point {
        .init(x: Double(point.x), y: 1 - Double(point.y))
    }

    private static func isUsable(_ quad: QuadPoints) -> Bool {
        guard quad.isValidForEditing, !quad.isFullImage else { return false }

        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        // Área de Shoelace. Evita proponer para recorte una franja estrecha,
        // una observación degenerada o una detección claramente errónea.
        let area = zip(points, points.dropFirst() + [points[0]]).reduce(0.0) { partial, pair in
            partial + (pair.0.x * pair.1.y) - (pair.1.x * pair.0.y)
        }
        return abs(area) >= 0.12
    }
}
