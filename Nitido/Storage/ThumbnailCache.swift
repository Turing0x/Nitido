import SwiftUI

/// Caché en memoria de miniaturas ya decodificadas.
///
/// Las miniaturas se pueden perder (se excluyen de la copia de seguridad y se
/// pueden borrar para liberar espacio). Si el fichero no existe al pintar la
/// celda hay que regenerarlo desde el procesado en lugar de mostrar un hueco;
/// esa regeneración llega en la Sprint 1, junto con `Downsampler`.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        // Techo aproximado en número de imágenes, no en bytes: las miniaturas
        // tienen el lado mayor a 400 px, así que el coste por entrada es bajo.
        cache.countLimit = 240
    }

    func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, forKey key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
