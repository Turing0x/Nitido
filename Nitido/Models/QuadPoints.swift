import Foundation

/// Los cuatro vértices del recorte, normalizados (0...1) sobre la imagen
/// original. Se guardan normalizados para que el recorte sea reversible y
/// reeditable aunque cambie la resolución de la imagen de trabajo.
struct QuadPoints: Codable, Sendable, Hashable {
    enum Corner: CaseIterable, Sendable, Hashable {
        case topLeft
        case topRight
        case bottomRight
        case bottomLeft
    }

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

    /// Mantiene el recorte visual al girar la página 90º en sentido horario.
    /// Las coordenadas usan el sistema de la interfaz: origen arriba a la
    /// izquierda y Y positiva hacia abajo. Después de rotar, cada vértice
    /// vuelve a su esquina nominal para que los tiradores no se cruzan.
    func rotatedClockwise() -> QuadPoints {
        func rotate(_ point: Point) -> Point {
            .init(x: 1 - point.y, y: point.x)
        }

        return QuadPoints(
            topLeft: rotate(bottomLeft),
            topRight: rotate(topLeft),
            bottomRight: rotate(topRight),
            bottomLeft: rotate(bottomRight)
        )
    }

    var isFullImage: Bool {
        self == .full
    }

    func replacing(_ corner: Corner, with point: Point) -> QuadPoints {
        var copy = self
        switch corner {
        case .topLeft: copy.topLeft = point
        case .topRight: copy.topRight = point
        case .bottomRight: copy.bottomRight = point
        case .bottomLeft: copy.bottomLeft = point
        }
        return copy
    }

    /// Impide que un tirador salga de la imagen o convierta el recorte en un
    /// lazo. Core Image necesita un cuadrilátero convexo y con área positiva.
    var isValidForEditing: Bool {
        let points = [topLeft, topRight, bottomRight, bottomLeft]
        guard points.allSatisfy({ (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            return false
        }

        var signs: [Double] = []
        for index in points.indices {
            let first = points[index]
            let second = points[(index + 1) % points.count]
            let third = points[(index + 2) % points.count]
            let cross = (second.x - first.x) * (third.y - second.y)
                - (second.y - first.y) * (third.x - second.x)
            signs.append(cross)
        }
        guard signs.allSatisfy({ abs($0) > 0.0001 }) else { return false }
        return signs.allSatisfy({ $0 > 0 }) || signs.allSatisfy({ $0 < 0 })
    }
}
