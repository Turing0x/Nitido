import Foundation

/// Caja de una observación de texto reconocido.
///
/// Las coordenadas son **normalizadas (0...1) y con el origen abajo a la
/// izquierda**, es decir el espacio de coordenadas que devuelve Vision tal cual.
/// No se convierten al guardar: la conversión al espacio de destino (UIKit,
/// contexto PDF) se hace en el punto de dibujo, que es donde se puede verificar
/// visualmente. Ver `PDFExporter` (Sprint 4).
struct OCRBox: Codable, Sendable, Hashable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double

    init(text: String, x: Double, y: Double, width: Double, height: Double, confidence: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = confidence
    }
}

extension Array where Element == OCRBox {
    /// Orden de lectura humano: primero por franja vertical (de arriba abajo en
    /// pantalla, o sea de mayor a menor `y` en coordenadas de Vision) y dentro
    /// de cada franja de izquierda a derecha. Vision no garantiza este orden y
    /// sin esto el texto plano de un documento a dos columnas sale mezclado.
    func inReadingOrder(lineTolerance: Double = 0.01) -> [OCRBox] {
        sorted { lhs, rhs in
            if abs(lhs.y - rhs.y) > lineTolerance { return lhs.y > rhs.y }
            return lhs.x < rhs.x
        }
    }
}
