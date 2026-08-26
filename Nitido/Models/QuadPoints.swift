import Foundation

/// Los cuatro vértices del recorte, normalizados (0...1) sobre la imagen
/// original. Se guardan normalizados para que el recorte sea reversible y
/// reeditable aunque cambie la resolución de la imagen de trabajo.
struct QuadPoints: Codable, Sendable, Hashable {
    struct Point: Codable, Sendable, Hashable {
        var x: Double
        var y: Double
    }

    var topLeft: Point
    var topRight: Point
    var bottomRight: Point
    var bottomLeft: Point

    /// Cuadrilátero que cubre la imagen entera (sin recorte).
    static let full = QuadPoints(
        topLeft: .init(x: 0, y: 0),
        topRight: .init(x: 1, y: 0),
        bottomRight: .init(x: 1, y: 1),
        bottomLeft: .init(x: 0, y: 1)
    )
}
