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
    /// `QuadPoints` serializado.
    var quadData: Data?
    var ocrText: String = ""
    /// `[OCRBox]` serializado.
    var ocrBoxesData: Data?

    var document: ScanDocument?

    init(
        id: UUID = UUID(),
        index: Int,
        originalFileName: String,
        processedFileName: String,
        thumbnailFileName: String,
        rotation: Int = 0,
        filter: PageFilter = .original,
        quad: QuadPoints? = nil,
        ocrText: String = "",
        ocrBoxes: [OCRBox] = []
    ) {
        self.id = id
        self.index = index
        self.originalFileName = originalFileName
        self.processedFileName = processedFileName
        self.thumbnailFileName = thumbnailFileName
        self.rotation = rotation
        self.filterRaw = filter.rawValue
        self.quad = quad
        self.ocrText = ocrText
        self.ocrBoxes = ocrBoxes
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
