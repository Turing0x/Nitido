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

    /// Degradado con una banda oscura, para que un filtro de documento tenga
    /// algo que mejorar y el test no dependa de un gris plano.
    static func gradientImage(width: Int = 240, height: Int = 320) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        for y in 0..<height {
            let t = CGFloat(y) / CGFloat(max(height - 1, 1))
            context.setFillColor(CGColor(red: 0.55 + 0.35 * t, green: 0.5, blue: 0.45, alpha: 1))
            context.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        context.fill(CGRect(x: 24, y: 24, width: width - 48, height: 18))
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

    @Test("la previsualización aplica filtros sin superar su límite de tamaño")
    func previewAppliesNonDestructivePipeline() throws {
        let source = TestFixtures.image(width: 2_400, height: 3_000)
        for filter in PageFilter.allCases {
            let configuration = PageEditConfiguration(
                rotation: 90,
                filter: filter,
                documentEnhancementIntensity: 0.6,
                quad: .full
            )
            let preview = try PageRenderer.preview(source, configuration: configuration)
            #expect(max(preview.width, preview.height) <= Int(PageRenderer.previewMaxPixelSize))
        }
        #expect(source.width == 2_400)
        #expect(source.height == 3_000)
    }

    @Test("la corrección de perspectiva produce una página utilizable")
    func perspectiveCorrectionRendersQuad() throws {
        let source = TestFixtures.image(width: 800, height: 1_000)
        let rendered = try PageRenderer.preview(
            source,
            configuration: PageEditConfiguration(
                quad: QuadPoints(
                    topLeft: .init(x: 0.08, y: 0.05),
                    topRight: .init(x: 0.93, y: 0.12),
                    bottomRight: .init(x: 0.88, y: 0.94),
                    bottomLeft: .init(x: 0.14, y: 0.89)
                )
            )
        )

        #expect(rendered.width > 0)
        #expect(rendered.height > 0)
    }

    @Test("la intensidad de Documento cambia el resultado")
    func documentIntensityChangesOutput() throws {
        let source = TestFixtures.gradientImage(width: 240, height: 320)
        let original = try PageRenderer.preview(source, configuration: PageEditConfiguration())
        let enhanced = try PageRenderer.preview(
            source,
            configuration: PageEditConfiguration(filter: .document, documentEnhancementIntensity: 1)
        )
        #expect(try ImageProcessor.encodeProcessed(original) != ImageProcessor.encodeProcessed(enhanced))
        #expect(source.width == 240)
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

    @Test("un cuadrilátero detectado recorta el procesado y no toca el original")
    func detectedQuadIsAppliedNonDestructively() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let source = TestFixtures.image(width: 240, height: 300)
        let quad = QuadPoints(
            topLeft: .init(x: 0.1, y: 0.1),
            topRight: .init(x: 0.9, y: 0.1),
            bottomRight: .init(x: 0.9, y: 0.9),
            bottomLeft: .init(x: 0.1, y: 0.9)
        )
        let records = try PageIngestor(fileStore: store).ingest(
            [SendableImage(source)],
            documentID: documentID,
            detectedQuads: [quad]
        )
        let record = try #require(records.first)
        let original = try store.read(fileName: record.originalFileName, documentID: documentID)
        let processed = try store.read(fileName: record.processedFileName, documentID: documentID)
        let originalImage = try #require(Downsampler.fullImage(from: original)?.cgImage)
        let processedImage = try #require(Downsampler.fullImage(from: processed)?.cgImage)

        #expect(record.quad == quad)
        #expect(record.filter == .document)
        #expect(originalImage.width == 240)
        #expect(originalImage.height == 300)
        #expect(processedImage.width < originalImage.width)
        #expect(processedImage.height < originalImage.height)
    }

    @Test("una imagen sin documento no inventa un recorte")
    func detectionFailsOpen() async {
        let blank = TestFixtures.image(width: 200, height: 200)
        let quad = await DocumentQuadDetector.detect(in: blank)
        #expect(quad == nil)
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

    @Test("editar, reordenar y eliminar una página mantiene el documento consistente")
    func editsReordersAndDeletesPage() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let records = makeRecords(3)
        let id = try await store.createDocument(title: "Factura", records: records)

        let configuration = PageEditConfiguration(
            rotation: 90,
            filter: .document,
            documentEnhancementIntensity: 0.4,
            quad: QuadPoints(
                topLeft: .init(x: 0.1, y: 0.1),
                topRight: .init(x: 0.9, y: 0.1),
                bottomRight: .init(x: 0.9, y: 0.9),
                bottomLeft: .init(x: 0.1, y: 0.9)
            )
        )
        try await store.updatePage(records[0].pageID, in: id, configuration: configuration)
        try await store.reorderPages(Array(records.map(\.pageID).reversed()), in: id)
        let removed = try await store.deletePage(records[1].pageID, in: id)

        #expect(removed.originalFileName == records[1].originalFileName)
        #expect(try await store.nextPageIndex(for: id) == 2)
        #expect(try await store.pageFileNames(for: id).count == 6)

        let remainingIDs = Array(records.map(\.pageID).reversed().filter { $0 != records[1].pageID })
        let first = try await store.pageAssetInfo(pageID: remainingIDs[0], in: id)
        #expect(first.originalFileName == records[2].originalFileName)
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

    @Test("mover varios documentos a la papelera los marca todos y de un solo golpe")
    func batchTrash() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let a = try await store.createDocument(title: "A", records: makeRecords(1))
        let b = try await store.createDocument(title: "B", records: makeRecords(1))
        let c = try await store.createDocument(title: "C", records: makeRecords(1))

        try await store.moveToTrash([a, b])

        let context = ModelContext(container)
        func deletedAt(_ id: UUID) throws -> Date? {
            try #require(
                try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == id })).first
            ).deletedAt
        }
        #expect(try deletedAt(a) != nil)
        #expect(try deletedAt(b) != nil)
        #expect(try deletedAt(c) == nil)
    }

    @Test("borrar definitivamente quita el documento y sus páginas de SwiftData")
    func permanentlyDeleteRemovesDocument() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let id = try await store.createDocument(title: "Recibo", records: makeRecords(2))
        try await store.moveToTrash(id)

        try await store.permanentlyDelete(id)

        let context = ModelContext(container)
        let remaining = try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == id }))
        #expect(remaining.isEmpty)
        let remainingPages = try context.fetch(FetchDescriptor<ScanPage>())
        #expect(remainingPages.isEmpty)
    }

    @Test("expiredTrash solo devuelve lo borrado antes del corte, no lo reciente ni lo activo")
    func expiredTrashRespectsCutoff() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let old = try await store.createDocument(title: "Viejo", records: makeRecords(1))
        let recent = try await store.createDocument(title: "Reciente", records: makeRecords(1))
        let active = try await store.createDocument(title: "Activo", records: makeRecords(1))

        try await store.moveToTrash(old)
        try await store.moveToTrash(recent)
        _ = active

        let context = ModelContext(container)
        let oldDocument = try #require(
            try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == old })).first
        )
        oldDocument.deletedAt = Calendar.current.date(byAdding: .day, value: -31, to: .now)
        try context.save()

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let expired = try await store.expiredTrash(before: cutoff)
        #expect(expired == [old])
    }

    @Test("mover varios documentos de carpeta los deja todos en la misma")
    func batchMoveDocuments() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let a = try await store.createDocument(title: "A", records: makeRecords(1))
        let b = try await store.createDocument(title: "B", records: makeRecords(1))
        let folderID = try await store.createFolder(name: "Facturas")

        try await store.moveDocuments([a, b], toFolder: folderID)

        let context = ModelContext(container)
        let folder = try #require(
            try context.fetch(FetchDescriptor<ScanFolder>(predicate: #Predicate { $0.id == folderID })).first
        )
        #expect(Set(folder.documents.map(\.id)) == Set([a, b]))
    }

    @Test("setOCRFailed marca la página y un OCR posterior con éxito lo limpia")
    func ocrFailedFlag() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let records = makeRecords(1)
        let pageID = records[0].pageID
        let documentID = try await store.createDocument(title: "Contrato", records: records)

        try await store.setOCRFailed(pageID, in: documentID)
        let context = ModelContext(container)
        func page() throws -> ScanPage {
            try #require(try context.fetch(FetchDescriptor<ScanPage>(predicate: #Predicate { $0.id == pageID })).first)
        }
        #expect(try page().ocrFailed == true)

        try await store.setOCRResult(PageOCRUpdate(pageID: pageID, text: "hola", boxes: []), in: documentID)
        #expect(try page().ocrFailed == false)
    }

    @Test("el OCR de una página recalcula el texto de búsqueda del documento")
    func setOCRResultRecomputesSearchText() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let records = makeRecords(3)
        let id = try await store.createDocument(title: "Factura", records: records)

        let boxes = [OCRBox(text: "Total", x: 0.1, y: 0.8, width: 0.2, height: 0.03, confidence: 0.95)]
        let summary1 = try await store.setOCRResult(
            PageOCRUpdate(pageID: records[0].pageID, text: "Total 42 euros", boxes: boxes),
            in: id
        )
        #expect(summary1.searchText == "Total 42 euros")

        // Una página sin texto reconocido (todavía vacía) queda excluida del join.
        let summary2 = try await store.setOCRResult(
            PageOCRUpdate(pageID: records[2].pageID, text: "Página final", boxes: []),
            in: id
        )
        #expect(summary2.searchText == "Total 42 euros\nPágina final")

        let assets = try await store.pageAssetInfo(pageID: records[0].pageID, in: id)
        #expect(assets == PageAssetInfo(
            originalFileName: records[0].originalFileName,
            processedFileName: records[0].processedFileName,
            thumbnailFileName: records[0].thumbnailFileName
        ))
    }

    @Test("un documento que no existe da documentNotFound")
    func missingDocument() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        await #expect(throws: DocumentStoreError.self) {
            try await store.rename(UUID(), to: "x")
        }
    }

    @Test("las carpetas se numeran por orden de creación y se pueden renombrar")
    func createsAndRenamesFolders() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        let firstID = try await store.createFolder(name: "Facturas")
        let secondID = try await store.createFolder(name: "  Contratos  ")
        try await store.renameFolder(firstID, to: "  Facturas 2026  ")
        // Un nombre en blanco no debe dejar la carpeta sin nombre.
        try await store.renameFolder(secondID, to: "   ")

        let context = ModelContext(container)
        let folders = try context.fetch(FetchDescriptor<ScanFolder>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(folders.map(\.id) == [firstID, secondID])
        #expect(folders[0].name == "Facturas 2026")
        #expect(folders[1].name == "Contratos")
    }

    @Test("mover un documento de carpeta actualiza la relación en ambos sentidos")
    func movesDocumentBetweenFolders() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let documentID = try await store.createDocument(title: "Recibo", records: [])
        let folderID = try await store.createFolder(name: "Recibos")

        try await store.moveDocument(documentID, toFolder: folderID)
        let context = ModelContext(container)
        func fetchDocument() throws -> ScanDocument {
            try #require(
                try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == documentID })).first
            )
        }
        #expect(try fetchDocument().folder?.id == folderID)

        try await store.moveDocument(documentID, toFolder: nil)
        #expect(try fetchDocument().folder == nil)
    }

    @Test("borrar una carpeta deja sus documentos sin carpeta, no los borra")
    func deletingFolderNullifiesDocuments() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let documentID = try await store.createDocument(title: "Contrato", records: [])
        let folderID = try await store.createFolder(name: "Legal")
        try await store.moveDocument(documentID, toFolder: folderID)

        try await store.deleteFolder(folderID)

        let context = ModelContext(container)
        let document = try #require(
            try context.fetch(FetchDescriptor<ScanDocument>(predicate: #Predicate { $0.id == documentID })).first
        )
        #expect(document.folder == nil)
        let folders = try context.fetch(FetchDescriptor<ScanFolder>())
        #expect(folders.isEmpty)
    }

    @Test("mover a una carpeta que no existe da folderNotFound")
    func missingFolder() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let documentID = try await store.createDocument(title: "Nómina", records: [])

        await #expect(throws: DocumentStoreError.self) {
            try await store.moveDocument(documentID, toFolder: UUID())
        }
    }
}
