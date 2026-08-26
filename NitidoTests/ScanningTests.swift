import CoreGraphics
import Foundation
import SwiftData
import Testing
import UIKit
@testable import Nitido

/// Utilidades compartidas por los tests de captura.
enum TestFixtures {
    /// Imagen sólida del tamaño pedido.
    static func image(width: Int = 800, height: Int = 1000) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: width - 80, height: 30))
        return context.makeImage()!
    }

    /// PDF de `pageCount` páginas A4.
    static func pdf(pageCount: Int) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                let text = "Página \(index + 1)" as NSString
                text.draw(at: CGPoint(x: 40, y: 40), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 24)
                ])
            }
        }
    }

    static func makeFileStore() throws -> (LocalFileStore, URL) {
        let root = URL.temporaryDirectory
            .appending(path: "NitidoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LocalFileStore(containerRoot: root)
        try store.prepareRoot()
        return (store, root)
    }
}

@Suite("Procesado de imagen")
struct ImageProcessorTests {

    @Test("el original se codifica y se puede volver a leer")
    func encodesOriginal() throws {
        let image = TestFixtures.image()
        let encoded = try ImageProcessor.encodeOriginal(image)

        #expect(!encoded.data.isEmpty)
        #expect(["heic", "jpg"].contains(encoded.fileExtension))

        // Lo importante no es qué formato salga, sino que lo que se guarda se
        // pueda volver a decodificar.
        let reloaded = Downsampler.fullImage(from: encoded.data)
        #expect(reloaded != nil)
        #expect(reloaded?.cgImage.width == image.width)
    }

    @Test("la miniatura respeta el lado mayor")
    func thumbnailRespectsMaxSize() throws {
        let data = try ImageProcessor.encodeProcessed(TestFixtures.image(width: 2000, height: 3000))
        let thumbnail = Downsampler.thumbnail(from: data, maxPixelSize: 400)

        let thumbnail2 = try #require(thumbnail)
        #expect(max(thumbnail2.width, thumbnail2.height) == 400)
    }

    @Test("normalizar una imagen girada intercambia los lados")
    func normalizeSwapsSides() {
        let image = TestFixtures.image(width: 800, height: 1000)
        let normalized = ImageProcessor.normalized(SendableImage(image, orientation: .right))

        #expect(normalized.width == 1000)
        #expect(normalized.height == 800)
    }
}

@Suite("Importación")
struct ImageImporterTests {

    @Test("un PDF de tres páginas entra como tres imágenes")
    func rasterizesEveryPDFPage() throws {
        let images = try ImageImporter.rasterize(pdf: TestFixtures.pdf(pageCount: 3))

        #expect(images.count == 3)
        for image in images {
            #expect(image.cgImage.width > 0)
            // A4 vertical: más alto que ancho.
            #expect(image.cgImage.height > image.cgImage.width)
        }
    }

    @Test("el rasterizado no se pasa del lado mayor permitido")
    func respectsMaxPixelSize() throws {
        let images = try ImageImporter.rasterize(pdf: TestFixtures.pdf(pageCount: 1))
        let image = try #require(images.first)

        #expect(CGFloat(max(image.cgImage.width, image.cgImage.height))
                <= ImageImporter.pdfMaxPixelSize)
    }

    @Test("unos datos que no son una imagen dan error")
    func rejectsGarbage() {
        #expect(throws: ImageImportError.self) {
            try ImageImporter.images(fromImageData: [Data("no soy una imagen".utf8)])
        }
    }
}

@Suite("Ingesta de páginas")
struct PageIngestorTests {

    @Test("cada página deja original, procesado y miniatura en disco")
    func writesThreeFilesPerPage() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let ingestor = PageIngestor(fileStore: store)
        let records = try ingestor.ingest(
            [SendableImage(TestFixtures.image()), SendableImage(TestFixtures.image())],
            documentID: documentID
        )

        #expect(records.count == 2)
        #expect(records.map(\.index) == [0, 1])

        for record in records {
            #expect(store.fileExists(fileName: record.originalFileName, documentID: documentID))
            #expect(store.fileExists(fileName: record.processedFileName, documentID: documentID))
            #expect(store.fileExists(fileName: record.thumbnailFileName, documentID: documentID))
        }
    }

    @Test("añadir páginas continúa la numeración")
    func continuesIndexing() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let ingestor = PageIngestor(fileStore: store)
        _ = try ingestor.ingest([SendableImage(TestFixtures.image())], documentID: documentID)
        let more = try ingestor.ingest(
            [SendableImage(TestFixtures.image())],
            documentID: documentID,
            startingIndex: 1
        )

        #expect(more.map(\.index) == [1])
    }

    @Test("el progreso se informa página a página")
    func reportsProgress() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let box = Mutex<[Int]>([])
        let ingestor = PageIngestor(fileStore: store)
        _ = try ingestor.ingest(
            (0..<3).map { _ in SendableImage(TestFixtures.image(width: 200, height: 300)) },
            documentID: UUID(),
            onProgress: { done, _ in box.append(done) }
        )

        #expect(box.value == [1, 2, 3])
    }

    /// Pequeño buzón con cerrojo, solo para recoger el progreso desde el
    /// closure `@Sendable` del test.
    final class Mutex<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Value

        init(_ value: Value) { storage = value }

        var value: Value {
            lock.lock(); defer { lock.unlock() }
            return storage
        }

        func append(_ element: Int) where Value == [Int] {
            lock.lock(); defer { lock.unlock() }
            storage.append(element)
        }
    }
}

@Suite("DocumentStore")
struct DocumentStoreTests {

    private func makeRecords(_ count: Int) -> [PageRecord] {
        (0..<count).map { index in
            let pageID = UUID()
            return PageRecord(
                pageID: pageID,
                index: index,
                originalFileName: "original-\(pageID).heic",
                processedFileName: "processed-\(pageID).jpg",
                thumbnailFileName: "thumb-\(pageID).jpg"
            )
        }
    }

    @Test("crear un documento guarda sus páginas en orden")
    func createsDocument() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        let id = try await store.createDocument(title: "Factura", records: makeRecords(3))
        #expect(try await store.nextPageIndex(for: id) == 3)
    }

    @Test("añadir páginas continúa donde lo dejó")
    func appendsPages() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        let id = try await store.createDocument(title: "Contrato", records: makeRecords(2))
        let next = try await store.nextPageIndex(for: id)
        let extra = makeRecords(1).map {
            PageRecord(
                pageID: $0.pageID,
                index: next,
                originalFileName: $0.originalFileName,
                processedFileName: $0.processedFileName,
                thumbnailFileName: $0.thumbnailFileName
            )
        }
        try await store.appendPages(extra, to: id)

        #expect(try await store.nextPageIndex(for: id) == 3)
        #expect(try await store.pageFileNames(for: id).count == 9)
    }

    @Test("renombrar ignora un título en blanco")
    func renameIgnoresBlank() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let id = try await store.createDocument(title: "Original", records: [])

        try await store.rename(id, to: "   ")
        // Si el título se hubiera borrado, la biblioteca mostraría una fila vacía.
        try await store.rename(id, to: "  Nuevo  ")

        let context = ModelContext(container)
        let document = try #require(
            try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == id })).first
        )
        #expect(document.title == "Nuevo")
    }

    @Test("la papelera es un borrado lógico y se puede deshacer")
    func trashIsReversible() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let id = try await store.createDocument(title: "Nómina", records: makeRecords(1))

        try await store.moveToTrash(id)
        let context = ModelContext(container)
        func fetch() throws -> ScanDocument {
            try #require(
                try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == id })).first
            )
        }
        #expect(try fetch().deletedAt != nil)

        try await store.restoreFromTrash(id)
        #expect(try fetch().deletedAt == nil)
    }

    @Test("un documento que no existe da documentNotFound")
    func missingDocument() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        await #expect(throws: DocumentStoreError.self) {
            try await store.rename(UUID(), to: "x")
        }
    }
}
