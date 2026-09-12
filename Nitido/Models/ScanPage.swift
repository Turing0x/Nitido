import Foundation
import SwiftData

@Model
final class ScanPage {
    var id: UUID = UUID()
    var index: Int = 0

    // Nombres de fichero **relativos** al directorio del documento.
    // Nunca rutas absolutas: el contenedor de la app cambia de UUID entre
    // instalaciones y actualizaciones y todas las imágenes dejarían de
    // encontrarse. La ruta se reconstruye en tiempo de ejecución con FileStore.
    var originalFileName: String = ""
    var processedFileName: String = ""
    var thumbnailFileName: String = ""

    /// 0, 90, 180 o 270.
    var rotation: Int = 0
    var filterRaw: String = PageFilter.original.rawValue
    /// Intensidad de `CIDocumentEnhancer`. Se guarda para que el filtro
    /// Documento sea reversible y editable igual que el resto de ajustes.
    var documentEnhancementIntensity: Double = 1
    /// `QuadPoints` serializado.
    var quadData: Data?
    var ocrText: String = ""
    /// `[OCRBox]` serializado.
    var ocrBoxesData: Data?
    /// El reconocimiento se intentó y falló (no distingue "aún no se ha
    /// intentado" de "se intentó y no encontró texto", que en ambos casos
    /// deja `ocrText` vacío pero no debe ofrecer reintentar).
    var ocrFailed: Bool = false
    /// La página ya gastó su unidad de la cuota mensual del plan gratuito.
    /// Se marca en el primer reconocimiento y no se vuelve a mirar: reintentar
    /// tras un fallo, o rehacer las cajas tras recortar, no cuesta cuota.
    var ocrCounted: Bool = false
    /// Se quedó sin reconocer porque la cuota del mes estaba agotada. Distinto
    /// de `ocrFailed`, que es un error de verdad: esto se resuelve solo al
    /// empezar el mes siguiente o al comprar Pro.
    var ocrDeferred: Bool = false

    var document: ScanDocument?

    init(
        id: UUID = UUID(),
        index: Int,
        originalFileName: String,
        processedFileName: String,
        thumbnailFileName: String,
        rotation: Int = 0,
        filter: PageFilter = .original,
        documentEnhancementIntensity: Double = 1,
        quad: QuadPoints? = nil,
        ocrText: String = "",
        ocrBoxes: [OCRBox] = [],
        ocrFailed: Bool = false
    ) {
        self.id = id
        self.index = index
        self.originalFileName = originalFileName
        self.processedFileName = processedFileName
        self.thumbnailFileName = thumbnailFileName
        self.rotation = rotation
        self.filterRaw = filter.rawValue
        self.documentEnhancementIntensity = documentEnhancementIntensity
        self.quad = quad
        self.ocrText = ocrText
        self.ocrBoxes = ocrBoxes
        self.ocrFailed = ocrFailed
    }

    var filter: PageFilter {
        get { PageFilter(rawValue: filterRaw) ?? .original }
        set { filterRaw = newValue.rawValue }
    }

    var quad: QuadPoints? {
        get { quadData.flatMap { try? JSONDecoder().decode(QuadPoints.self, from: $0) } }
        set { quadData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var ocrBoxes: [OCRBox] {
        get { ocrBoxesData.flatMap { try? JSONDecoder().decode([OCRBox].self, from: $0) } ?? [] }
        set { ocrBoxesData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
}
