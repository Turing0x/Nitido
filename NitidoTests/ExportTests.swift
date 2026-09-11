import CoreGraphics
import Foundation
import PDFKit
import SwiftData
import Testing
import UIKit
@testable import Nitido

@Suite("Coordenadas de exportación")
struct PDFCoordinateMappingTests {

    @Test("una caja en la parte de arriba de la imagen (Vision) queda arriba en el PDF (UIKit)")
    func topBoxMapsToTop() {
        // En Vision, y alto = arriba de la imagen. Una caja con y=0.9 está
        // pegada al borde superior.
        let box = OCRBox(text: "arriba", x: 0.1, y: 0.9, width: 0.2, height: 0.05, confidence: 1)
        let imageRect = CGRect(x: 0, y: 0, width: 1000, height: 2000)
        let rect = pdfRect(for: box, in: imageRect)

        // En el espacio de destino (UIKit, Y hacia abajo) "arriba" es minY
        // pequeño, no grande.
        #expect(rect.minY < imageRect.height * 0.1)
    }

    @Test("una caja en la parte de abajo de la imagen (Vision) queda abajo en el PDF (UIKit)")
    func bottomBoxMapsToBottom() {
        let box = OCRBox(text: "abajo", x: 0.1, y: 0.02, width: 0.2, height: 0.05, confidence: 1)
        let imageRect = CGRect(x: 0, y: 0, width: 1000, height: 2000)
        let rect = pdfRect(for: box, in: imageRect)

        #expect(rect.maxY > imageRect.height * 0.9)
    }

    @Test("una caja a todo el ancho ocupa todo el ancho del rect de destino")
    func fullWidthBoxSpansImageRect() {
        let box = OCRBox(text: "ancho completo", x: 0, y: 0.5, width: 1, height: 0.05, confidence: 1)
        let imageRect = CGRect(x: 10, y: 20, width: 800, height: 600)
        let rect = pdfRect(for: box, in: imageRect)

        #expect(rect.minX == imageRect.minX)
        #expect(rect.width == imageRect.width)
    }

    @Test("el rectángulo de destino respeta un imageRect desplazado (A4/Carta)")
    func honorsOffsetImageRect() {
        let box = OCRBox(text: "x", x: 0.5, y: 0.5, width: 0.1, height: 0.1, confidence: 1)
        let imageRect = CGRect(x: 36, y: 36, width: 500, height: 700)
        let rect = pdfRect(for: box, in: imageRect)

        #expect(imageRect.contains(rect))
    }
}

@Suite("Ajuste del tamaño de fuente")
struct FontFittingTests {

    @Test("doblar el ancho de la caja dobla aproximadamente el tamaño de fuente")
    func scalesProportionally() {
        let base = PDFExporter.fittedFontSize(forBoxWidth: 100, measuredWidth: 200)
        let doubled = PDFExporter.fittedFontSize(forBoxWidth: 200, measuredWidth: 200)

        #expect(doubled / base > 1.9 && doubled / base < 2.1)
    }

    @Test("una caja degenerada no produce un tamaño fuera de rango")
    func clampsDegenerateBoxes() {
        let tiny = PDFExporter.fittedFontSize(forBoxWidth: 0.001, measuredWidth: 200)
        let huge = PDFExporter.fittedFontSize(forBoxWidth: 100_000, measuredWidth: 1)

        #expect(tiny >= 1)
        #expect(huge <= 400)
    }
}

@Suite("Compresión")
struct PDFCompressionTests {

    private func sourceData() throws -> Data {
        try ImageProcessor.encodeProcessed(TestFixtures.image(width: 4_000, height: 5_000))
    }

    @Test("cada nivel respeta su lado mayor")
    func respectsMaxDimension() throws {
        let data = try sourceData()
        for level in PDFCompressionLevel.allCases {
            let image = try PDFCompression.compressedImage(from: data, level: level)
            #expect(CGFloat(max(image.width, image.height)) <= level.maxDimension)
        }
    }

    @Test("baja compresión pesa menos que alta para la misma fuente")
    func lowerLevelProducesSmallerData() throws {
        let data = try sourceData()
        let high = try PDFCompression.compressedJPEGData(from: data, level: .high)
        let low = try PDFCompression.compressedJPEGData(from: data, level: .low)

        #expect(low.count < high.count)
    }
}

@Suite("Saneado de nombre de fichero")
struct ImageExporterSanitizeTests {

    @Test("acentos, barras y símbolos se convierten en guiones")
    func sanitizesSpecialCharacters() {
        #expect(ImageExporter.sanitize("Factura Marzo/2026 (Ñoño)") == "Factura-Marzo-2026-Ñoño")
    }

    @Test("un título vacío cae a Nitido")
    func emptyTitleFallsBackToNitido() {
        #expect(ImageExporter.sanitize("") == "Nitido")
    }

    @Test("un título hecho solo de símbolos también cae a Nitido")
    func symbolsOnlyFallsBackToNitido() {
        #expect(ImageExporter.sanitize("***") == "Nitido")
    }
}

@Suite("DocumentStore — exportInfo")
struct DocumentStoreExportInfoTests {

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

    @Test("devuelve las páginas en orden con sus cajas de OCR")
    func returnsPagesInOrderWithOCRBoxes() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)
        let records = makeRecords(3)
        let id = try await store.createDocument(title: "Factura", records: records)

        let boxes = [OCRBox(text: "Total", x: 0.1, y: 0.1, width: 0.2, height: 0.03, confidence: 0.9)]
        try await store.setOCRResult(PageOCRUpdate(pageID: records[1].pageID, text: "Total 10€", boxes: boxes), in: id)

        let info = try await store.exportInfo(for: id)

        #expect(info.title == "Factura")
        #expect(info.pages.map(\.index) == [0, 1, 2])
        #expect(info.pages[1].ocrBoxes == boxes)
        #expect(info.pages[1].processedFileName == records[1].processedFileName)
        #expect(info.pages[0].ocrBoxes.isEmpty)
    }

    @Test("un documento inexistente lanza documentNotFound")
    func missingDocumentThrows() async throws {
        let container = try ModelContainer.nitidoInMemory()
        let store = DocumentStore(modelContainer: container)

        await #expect(throws: DocumentStoreError.self) {
            try await store.exportInfo(for: UUID())
        }
    }
}

@Suite("PDFExporter")
struct PDFExporterTests {

    @Test("el PDF generado se puede abrir y el texto invisible se encuentra donde se dibujó")
    func generatesSearchablePDF() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let pageID = UUID()
        let image = TestFixtures.image(width: 800, height: 1_000)
        let processedData = try ImageProcessor.encodeProcessed(image)
        let fileName = "processed-\(pageID).jpg"
        try store.write(processedData, fileName: fileName, documentID: documentID)

        // Caja centrada, en coordenadas de Vision (origen abajo-izquierda).
        let box = OCRBox(text: "FACTURA", x: 0.3, y: 0.45, width: 0.4, height: 0.08, confidence: 0.95)
        let info = DocumentExportInfo(
            documentID: documentID,
            title: "Factura de prueba",
            pages: [PageExportInfo(pageID: pageID, index: 0, processedFileName: fileName, ocrBoxes: [box])]
        )

        let data = try PDFExporter.export(info, options: PDFExportOptions(), fileStore: store)
        #expect(!data.isEmpty)

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)

        let selections = document.findString("FACTURA", withOptions: [])
        #expect(!selections.isEmpty)
    }

    @Test("sin capa de texto el PDF sale como imagen y no se puede buscar")
    func omitsTextLayerWhenDisabled() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let documentID = UUID()
        let pageID = UUID()
        let image = TestFixtures.image(width: 800, height: 1_000)
        let processedData = try ImageProcessor.encodeProcessed(image)
        let fileName = "processed-\(pageID).jpg"
        try store.write(processedData, fileName: fileName, documentID: documentID)

        let box = OCRBox(text: "FACTURA", x: 0.3, y: 0.45, width: 0.4, height: 0.08, confidence: 0.95)
        let info = DocumentExportInfo(
            documentID: documentID,
            title: "Factura de prueba",
            pages: [PageExportInfo(pageID: pageID, index: 0, processedFileName: fileName, ocrBoxes: [box])]
        )

        let data = try PDFExporter.export(
            info,
            options: PDFExportOptions(includesTextLayer: false),
            fileStore: store
        )

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1, "la imagen se sigue dibujando")
        #expect(document.findString("FACTURA", withOptions: []).isEmpty)
    }

    @Test("un documento sin páginas lanza noPages")
    func emptyDocumentThrows() throws {
        let (store, root) = try TestFixtures.makeFileStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let info = DocumentExportInfo(documentID: UUID(), title: "Vacío", pages: [])
        #expect(throws: PDFExporterError.self) {
            try PDFExporter.export(info, options: PDFExportOptions(), fileStore: store)
        }
    }
}

@Suite("Protección con contraseña")
struct PDFPasswordProtectorTests {

    @Test("un PDF protegido queda cifrado y solo se abre con la contraseña correcta")
    func roundTripsWithPassword() throws {
        let original = TestFixtures.pdf(pageCount: 1)
        let protectedData = try PDFPasswordProtector.protect(original, password: "s3cr3to")

        let document = try #require(PDFDocument(data: protectedData))
        #expect(document.isEncrypted)
        #expect(document.unlock(withPassword: "s3cr3to"))
    }

    @Test("una contraseña incorrecta no desbloquea el documento")
    func wrongPasswordFails() throws {
        let original = TestFixtures.pdf(pageCount: 1)
        let protectedData = try PDFPasswordProtector.protect(original, password: "correcta")

        let document = try #require(PDFDocument(data: protectedData))
        #expect(!document.unlock(withPassword: "incorrecta"))
    }

    @Test("sin protección pedida (nil) el PDF sale sin modificar")
    func noPasswordLeavesDataUnchanged() throws {
        let original = TestFixtures.pdf(pageCount: 1)
        let result = try PDFPasswordProtector.protect(original, password: nil)
        #expect(result == original)
    }

    /// La regresión que motivó el cambio de firma: con `password: ""` esta
    /// función devolvía el PDF **sin cifrar**, así que marcar "proteger con
    /// contraseña" y dejar el campo en blanco entregaba un fichero abierto que
    /// el usuario creía protegido. Ahora falla en vez de mentir.
    @Test("una contraseña vacía es un error, no un PDF sin cifrar")
    func emptyPasswordThrows() throws {
        let original = TestFixtures.pdf(pageCount: 1)
        #expect(throws: PDFPasswordProtectorError.emptyPassword) {
            try PDFPasswordProtector.protect(original, password: "")
        }
    }
}
