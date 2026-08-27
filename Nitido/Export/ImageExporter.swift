import Foundation

enum ImageExportFormat: String, CaseIterable, Sendable, Codable {
    case jpg
    case png
}

enum ImagePageSelection: Sendable {
    case all
    case single(pageID: UUID)
}

enum ImageExporterError: Error {
    case encodingFailed
}

/// Exporta páginas sueltas a JPG o PNG. "Todas las páginas" escribe un
/// fichero por página a un directorio temporal y devuelve todas las URLs
/// para un único `ShareLink(items:)` — sin zip, cero dependencias nuevas.
enum ImageExporter {
    static func exportURLs(
        for info: DocumentExportInfo,
        selection: ImagePageSelection,
        format: ImageExportFormat,
        compressionLevel: PDFCompressionLevel,
        fileStore: any FileStoring
    ) throws -> [URL] {
        let pages: [PageExportInfo]
        switch selection {
        case .all:
            pages = info.pages
        case .single(let pageID):
            pages = info.pages.filter { $0.pageID == pageID }
        }

        let sanitizedTitle = sanitize(info.title)
        var urls: [URL] = []
        for page in pages {
            try autoreleasepool {
                let sourceData = try fileStore.read(fileName: page.processedFileName, documentID: info.documentID)
                let raster = try PDFCompression.compressedImage(from: sourceData, level: compressionLevel)
                let data: Data?
                switch format {
                case .jpg: data = ImageProcessor.encodeJPEG(raster, quality: compressionLevel.jpegQuality)
                case .png: data = ImageProcessor.encodePNG(raster)
                }
                guard let data else { throw ImageExporterError.encodingFailed }

                let fileName = "\(sanitizedTitle)-p\(page.index + 1).\(format.rawValue)"
                let url = URL.temporaryDirectory.appending(path: fileName, directoryHint: .notDirectory)
                try data.write(to: url, options: .atomic)
                urls.append(url)
            }
        }
        return urls
    }

    /// Nombre de fichero saneado a partir del título del documento: sin
    /// caracteres problemáticos, para que sirva tal cual en cualquier sistema
    /// de ficheros y como nombre por defecto al exportar.
    static func sanitize(_ title: String) -> String {
        let base = title.isEmpty ? "Nitido" : title
        let parts = base.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "Nitido" : parts.joined(separator: "-")
    }
}
