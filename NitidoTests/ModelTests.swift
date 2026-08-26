import Foundation
import SwiftData
import Testing
@testable import Nitido

@Suite("Modelos")
struct ModelTests {

    @Test("el cuadrilátero y las cajas de OCR sobreviven al ida y vuelta")
    func codableRoundTrip() throws {
        let page = ScanPage(
            index: 0,
            originalFileName: "original-a.heic",
            processedFileName: "processed-a.jpg",
            thumbnailFileName: "thumb-a.jpg"
        )

        page.quad = .full
        page.ocrBoxes = [OCRBox(text: "Total", x: 0.1, y: 0.8, width: 0.2, height: 0.03, confidence: 0.97)]
        page.filter = .document

        #expect(page.quad == .full)
        #expect(page.ocrBoxes.first?.text == "Total")
        #expect(page.filterRaw == "document")
        #expect(page.filter == .document)
    }

    @Test("el orden de lectura ordena por franja y luego de izquierda a derecha")
    func readingOrder() {
        // Coordenadas de Vision: origen abajo a la izquierda, así que la línea
        // de arriba es la de mayor y.
        let boxes = [
            OCRBox(text: "derecha", x: 0.6, y: 0.90, width: 0.1, height: 0.02, confidence: 1),
            OCRBox(text: "abajo", x: 0.1, y: 0.20, width: 0.1, height: 0.02, confidence: 1),
            OCRBox(text: "izquierda", x: 0.1, y: 0.90, width: 0.1, height: 0.02, confidence: 1)
        ]

        #expect(boxes.inReadingOrder().map(\.text) == ["izquierda", "derecha", "abajo"])
    }

    @Test("las páginas se devuelven ordenadas por índice")
    func orderedPages() throws {
        let container = try ModelContainer.nitidoInMemory()
        let context = ModelContext(container)

        let document = ScanDocument(title: "Factura")
        context.insert(document)
        for index in [2, 0, 1] {
            let page = ScanPage(
                index: index,
                originalFileName: "original-\(index).heic",
                processedFileName: "processed-\(index).jpg",
                thumbnailFileName: "thumb-\(index).jpg"
            )
            page.document = document
            context.insert(page)
        }
        try context.save()

        #expect(document.orderedPages.map(\.index) == [0, 1, 2])
    }
}
