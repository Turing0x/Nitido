import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// Cómo se calcula el tamaño de cada página del PDF.
enum PDFPageSizeMode: String, CaseIterable, Sendable, Codable {
    case fitToImage
    case a4
    case letter
}

struct PDFExportOptions: Sendable {
    var pageSizeMode: PDFPageSizeMode = .fitToImage
    var compressionLevel: PDFCompressionLevel = .high
    /// Solo para desarrollo: si es `true`, el texto se dibuja visible en rojo
    /// en vez de en modo invisible, para comprobar a ojo que el eje Y está
    /// bien resuelto antes de ocultarlo. `UIColor` no es `Sendable` en este
    /// SDK (igual que `CGImage`, que en este proyecto necesita envolverse en
    /// `SendableImage`), así que el color de depuración vive como constante
    /// dentro de `PDFExporter` en vez de cruzar la frontera de actor como
    /// valor. Nunca se activa en release.
    var useDebugTextColor: Bool = false
    /// Dibujar o no la capa de texto invisible. Es lo que separa un PDF
    /// buscable de una imagen dentro de un PDF, y es función de Nítido Pro.
    /// Quien decide es `Entitlements`; aquí solo se obedece.
    var includesTextLayer: Bool = true

    init(
        pageSizeMode: PDFPageSizeMode = .fitToImage,
        compressionLevel: PDFCompressionLevel = .high,
        useDebugTextColor: Bool = false,
        includesTextLayer: Bool = true
    ) {
        self.pageSizeMode = pageSizeMode
        self.compressionLevel = compressionLevel
        self.useDebugTextColor = useDebugTextColor
        self.includesTextLayer = includesTextLayer
    }
}

enum PDFExporterError: Error {
    case noPages
    case pageImageUnreadable(pageID: UUID)
    case renderingFailed
}

/// Genera el PDF con `UIGraphicsPDFRenderer`: la imagen procesada de cada
/// página y, encima, el texto reconocido en modo invisible colocado sobre sus
/// cajas. El PDF resultante se ve como una foto y se puede seleccionar y
/// buscar como texto. La protección con contraseña se aplica después, sobre
/// estos bytes (ver `PDFPasswordProtector`); este tipo no sabe nada de eso.
enum PDFExporter {
    /// Márgenes de A4/Carta, en puntos (72 por pulgada). Es geometría de
    /// página impresa, no UI de la app: no sale de `DesignTokens`.
    static let printMargin: CGFloat = 36

    static let a4Size = CGSize(width: 595.28, height: 841.89)
    static let letterSize = CGSize(width: 612, height: 792)

    /// Tamaño de referencia al que se mide el ancho de cada cadena antes de
    /// escalar la fuente. Cualquier valor sirve —la fórmula es
    /// proporcional—; 100 pt da una medida precisa sin arrastrar redondeos.
    static let referenceFontSize: CGFloat = 100

    static func export(
        _ info: DocumentExportInfo,
        options: PDFExportOptions,
        fileStore: any FileStoring
    ) throws -> Data {
        guard !info.pages.isEmpty else { throw PDFExporterError.noPages }

        // Primer paso barato: el tamaño en píxeles de cada página sale de las
        // propiedades del fichero, sin decodificar la imagen entera, así se
        // puede calcular toda la geometría antes de abrir el renderer.
        let geometries = try info.pages.map { page -> (pageRect: CGRect, imageRect: CGRect) in
            let data = try fileStore.read(fileName: page.processedFileName, documentID: info.documentID)
            guard let pixelSize = Self.pixelSize(ofImageData: data) else {
                throw PDFExporterError.pageImageUnreadable(pageID: page.pageID)
            }
            return pageGeometry(forImagePixelSize: pixelSize, mode: options.pageSizeMode)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: geometries[0].pageRect)
        return renderer.pdfData { context in
            for (page, geometry) in zip(info.pages, geometries) {
                autoreleasepool {
                    context.beginPage(withBounds: geometry.pageRect, pageInfo: [:])
                    drawPage(
                        page,
                        geometry: geometry,
                        options: options,
                        fileStore: fileStore,
                        documentID: info.documentID,
                        cgContext: context.cgContext
                    )
                }
            }
        }
    }

    // MARK: - Geometría

    /// - `.fitToImage`: 1 px = 1 pt, sin márgenes. La "página" no tiene un
    ///   tamaño físico realista en pulgadas, pero Preview y Acrobat la
    ///   ajustan a la ventana igualmente, y evita inventar un DPI de
    ///   referencia que no se puede verificar.
    /// - `.a4`/`.letter`: imagen ajustada (aspect fit) y centrada dentro del
    ///   área imprimible, con `printMargin` de margen.
    private static func pageGeometry(
        forImagePixelSize pixelSize: CGSize,
        mode: PDFPageSizeMode
    ) -> (pageRect: CGRect, imageRect: CGRect) {
        switch mode {
        case .fitToImage:
            let rect = CGRect(origin: .zero, size: pixelSize)
            return (rect, rect)

        case .a4, .letter:
            let pageSize = mode == .a4 ? a4Size : letterSize
            let pageRect = CGRect(origin: .zero, size: pageSize)
            let printable = pageRect.insetBy(dx: printMargin, dy: printMargin)
            let scale = min(printable.width / pixelSize.width, printable.height / pixelSize.height)
            let fittedSize = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
            let imageRect = CGRect(
                x: printable.minX + (printable.width - fittedSize.width) / 2,
                y: printable.minY + (printable.height - fittedSize.height) / 2,
                width: fittedSize.width,
                height: fittedSize.height
            )
            return (pageRect, imageRect)
        }
    }

    /// Tamaño en píxeles leído de las propiedades del fichero, sin decodificar
    /// la imagen completa.
    private static func pixelSize(ofImageData data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat
        else { return nil }
        return CGSize(width: width, height: height)
    }

    // MARK: - Dibujo

    /// Página ilegible → se salta, no aborta el documento entero.
    private static func drawPage(
        _ page: PageExportInfo,
        geometry: (pageRect: CGRect, imageRect: CGRect),
        options: PDFExportOptions,
        fileStore: any FileStoring,
        documentID: UUID,
        cgContext: CGContext
    ) {
        autoreleasepool {
            guard let sourceData = try? fileStore.read(fileName: page.processedFileName, documentID: documentID),
                  let jpegData = try? PDFCompression.compressedJPEGData(from: sourceData, level: options.compressionLevel),
                  let raster = Self.jpegBackedImage(from: jpegData)
            else { return }

            UIImage(cgImage: raster).draw(in: geometry.imageRect)

            guard options.includesTextLayer else { return }
            for box in page.ocrBoxes where !box.text.isEmpty {
                drawInvisibleText(box, in: geometry.imageRect, cgContext: cgContext, useDebugColor: options.useDebugTextColor)
            }
        }
    }

    /// `UIGraphicsPDFRenderer` no conserva la compresión JPEG de un `CGImage`
    /// decodificado normalmente (vía `CGImageSource...CreateImage`/thumbnail):
    /// al dibujarlo, Core Graphics lo reincrusta como bitmap sin comprimir,
    /// que en un PDF real pesa varias veces más que el estimado (comprobado:
    /// un documento con un peso estimado de 4,5 MB salía con 28,3 MB reales).
    /// Construir el `CGImage` directamente desde un `CGDataProvider` de los
    /// bytes JPEG, con el inicializador `jpegDataProviderSource`, es la forma
    /// documentada de que Core Graphics reconozca el origen JPEG y empotre el
    /// mismo flujo comprimido en el PDF en vez de reescribirlo.
    private static func jpegBackedImage(from jpegData: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: jpegData as CFData) else { return nil }
        return CGImage(
            jpegDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func drawInvisibleText(
        _ box: OCRBox,
        in imageRect: CGRect,
        cgContext: CGContext,
        useDebugColor: Bool
    ) {
        let boxRect = pdfRect(for: box, in: imageRect)
        guard boxRect.width > 0, boxRect.height > 0 else { return }

        let referenceFont = UIFont.systemFont(ofSize: referenceFontSize)
        let measuredWidth = (box.text as NSString).size(withAttributes: [.font: referenceFont]).width
        guard measuredWidth > 0 else { return }

        let fittedSize = fittedFontSize(forBoxWidth: boxRect.width, measuredWidth: measuredWidth)
        let font = UIFont.systemFont(ofSize: fittedSize)

        let attributed = NSAttributedString(string: box.text, attributes: [
            .font: font,
            // El color es irrelevante en modo invisible; solo importa cuando
            // `useDebugColor` está activo para la verificación visual del eje Y.
            .foregroundColor: useDebugColor ? UIColor.red : UIColor.black
        ])

        cgContext.saveGState()
        if useDebugColor {
            cgContext.setTextDrawingMode(.fill)
        } else {
            // Vía principal del HANDOFF. Si en las pruebas manuales (Preview,
            // Adobe Reader) el texto no resulta buscable, sustituir esta rama
            // por `.fill` con `.foregroundColor: UIColor.clear` — cambio de
            // una línea, `attributed` ya sirve para ambos casos.
            cgContext.setTextDrawingMode(.invisible)
        }
        attributed.draw(at: boxRect.origin)
        cgContext.restoreGState()
    }

    /// La cadena medida al tamaño de referencia debe ocupar exactamente el
    /// ancho de la caja de Vision: se escala el tamaño de fuente en la misma
    /// proporción. Un tamaño fijo dejaría la selección desplazada respecto a
    /// lo que se ve (HANDOFF §9). Visibilidad de módulo (no `private`) para
    /// poder probar la fórmula sin pasar por `UIGraphicsPDFRenderer`.
    static func fittedFontSize(forBoxWidth boxWidth: CGFloat, measuredWidth: CGFloat) -> CGFloat {
        guard measuredWidth > 0 else { return referenceFontSize }
        return (referenceFontSize * boxWidth / measuredWidth).clamped(to: 1...400)
    }
}

private extension CGFloat {
    /// `CGFloat` tiene sus propias propiedades estáticas `min`/`max` (el
    /// valor representable más pequeño/grande), que aquí dentro tapan a las
    /// funciones globales `Swift.min`/`Swift.max` — de ahí la cualificación.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
