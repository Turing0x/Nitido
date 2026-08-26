import CoreGraphics
import Foundation
import ImageIO

/// Genera versiones reducidas sin decodificar la imagen entera.
///
/// `CGImageSourceCreateThumbnailAtIndex` decodifica directamente al tamaño
/// pedido. Es la diferencia entre abrir un documento de treinta páginas y que
/// la app muera por memoria.
enum Downsampler {

    static func thumbnail(from data: Data, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions()) else {
            return nil
        }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    static func thumbnail(from url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions()) else {
            return nil
        }
        return thumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    /// Imagen a resolución completa más su orientación EXIF, para importaciones.
    static func fullImage(from data: Data) -> SendableImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions()),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: raw) ?? .up
        return SendableImage(image, orientation: orientation)
    }

    /// `CFDictionary` no es `Sendable`, así que no puede ser una constante
    /// estática bajo concurrencia estricta. Se crea en cada llamada: es barato.
    private static func sourceOptions() -> CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private static func thumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Aplica la orientación EXIF al generar la miniatura, para que no
            // salga tumbada en la cuadrícula.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
