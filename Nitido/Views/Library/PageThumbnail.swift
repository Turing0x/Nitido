import SwiftUI

/// Miniatura de una página. Nunca mantiene la imagen a resolución completa:
/// carga el fichero de miniatura (lado mayor 400 px) y lo guarda en la caché
/// en memoria.
struct PageThumbnail: View {
    let documentID: UUID
    let thumbnailFileName: String
    let processedFileName: String

    @Environment(\.fileStore) private var fileStore
    @Environment(\.colorScheme) private var scheme
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                DS.ColorToken.muted(scheme)
                    .overlay {
                        Image(systemName: "doc")
                            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                    }
            }
        }
        .clipped()
        .task(id: thumbnailFileName) {
            await load()
        }
    }

    private func load() async {
        if let cached = ThumbnailCache.shared.image(forKey: thumbnailFileName) {
            image = cached
            return
        }

        let loader = ThumbnailLoader(fileStore: fileStore)
        let documentID = documentID
        let thumbnailFileName = thumbnailFileName
        let processedFileName = processedFileName

        // La lectura y el posible redimensionado no tocan el hilo principal.
        let data = await Task.detached(priority: .userInitiated) {
            loader.loadData(
                documentID: documentID,
                thumbnailFileName: thumbnailFileName,
                processedFileName: processedFileName
            )
        }.value

        guard let data, let decoded = UIImage(data: data) else { return }
        ThumbnailCache.shared.insert(decoded, forKey: thumbnailFileName)
        image = decoded
    }
}
