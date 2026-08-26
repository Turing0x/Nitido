import Foundation

/// Ajustes editables de una página. Es un valor plano para cruzar con
/// seguridad los límites de actor entre SwiftData, Core Image y SwiftUI.
struct PageEditConfiguration: Sendable, Equatable {
    var rotation: Int
    var filter: PageFilter
    var documentEnhancementIntensity: Double
    var quad: QuadPoints

    init(
        rotation: Int = 0,
        filter: PageFilter = .original,
        documentEnhancementIntensity: Double = 1,
        quad: QuadPoints = .full
    ) {
        self.rotation = Self.normalizedRotation(rotation)
        self.filter = filter
        self.documentEnhancementIntensity = documentEnhancementIntensity.clamped(to: 0...1)
        self.quad = quad
    }

    mutating func rotateClockwise() {
        rotation = Self.normalizedRotation(rotation + 90)
        quad = quad.rotatedClockwise()
    }

    static func normalizedRotation(_ value: Int) -> Int {
        let normalized = value % 360
        return normalized >= 0 ? normalized : normalized + 360
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
