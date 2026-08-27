import CoreGraphics

/// Convierte una `OCRBox` al rectángulo que ocupa dentro de `imageRect`, en el
/// espacio de dibujo de `UIGraphicsPDFRenderer` (puntos, origen arriba a la
/// izquierda: el mismo que usa UIKit para `draw(in:)` y para
/// `NSAttributedString.draw(at:)`).
///
/// Vision devuelve `OCRBox` normalizada (0...1) con origen **abajo** a la
/// izquierda: `y` crece hacia arriba. Por eso el borde superior de la caja en
/// el espacio de destino es `1 - (box.y + box.height)`, no `1 - box.y`. Es la
/// trampa del eje Y que señala el HANDOFF: Vision y UIKit miden la vertical al
/// revés uno del otro, y aquí es el único sitio donde se cruza esa frontera.
///
/// `imageRect` es un parámetro y no se asume igual a la página entera: la
/// misma función sirve para ajustar-a-imagen, A4 y Carta, cambiando solo el
/// rectángulo donde se ha dibujado la imagen (ver `PDFExporter`).
func pdfRect(for box: OCRBox, in imageRect: CGRect) -> CGRect {
    CGRect(
        x: imageRect.minX + box.x * imageRect.width,
        y: imageRect.minY + (1 - box.y - box.height) * imageRect.height,
        width: box.width * imageRect.width,
        height: box.height * imageRect.height
    )
}
