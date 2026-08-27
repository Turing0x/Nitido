import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Nitido

@Suite("Reconocimiento de texto")
struct TextRecognizerTests {

    /// Imagen en blanco con una palabra conocida dibujada, para poder
    /// comprobar que Vision la reconoce sin depender de una foto real.
    private func imageWithText(_ text: String, width: Int = 800, height: Int = 300) -> CGImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            (text as NSString).draw(
                at: CGPoint(x: 40, y: 100),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 48, weight: .semibold),
                    .foregroundColor: UIColor.black
                ]
            )
        }
        return image.cgImage!
    }

    @Test("reconoce una palabra dibujada y devuelve cajas normalizadas")
    func recognizesDrawnWord() async throws {
        let image = imageWithText("FACTURA")
        let result = try await TextRecognizer().recognize(image)

        #expect(result.text.uppercased().contains("FACTURA"))
        #expect(!result.boxes.isEmpty)
        for box in result.boxes {
            #expect((0...1).contains(box.x))
            #expect((0...1).contains(box.y))
            #expect(box.width > 0)
            #expect(box.height > 0)
        }
    }

    @Test("una imagen en blanco no produce cajas")
    func blankImageProducesNoBoxes() async throws {
        let image = imageWithText("")
        let result = try await TextRecognizer().recognize(image)
        #expect(result.boxes.isEmpty)
        #expect(result.text.isEmpty)
    }
}

@Suite("Búsqueda de documentos")
struct DocumentSearchTests {

    private func makeDocument(title: String, searchText: String) -> ScanDocument {
        ScanDocument(title: title, searchText: searchText)
    }

    @Test("una coincidencia de título aparece sin fragmento")
    func matchesTitleOnly() {
        let documents = [makeDocument(title: "Factura marzo", searchText: "")]
        let results = DocumentSearch.results(for: "marzo", in: documents)

        #expect(results.count == 1)
        #expect(results.first?.snippet == nil)
    }

    @Test("una coincidencia en el texto reconocido trae un fragmento con contexto")
    func matchesRecognizedText() throws {
        let text = String(repeating: "relleno ", count: 20) + "total a pagar 42 euros " + String(repeating: "relleno ", count: 20)
        let documents = [makeDocument(title: "Recibo", searchText: text)]
        let results = DocumentSearch.results(for: "pagar", in: documents)

        let snippet = try #require(results.first?.snippet)
        #expect(snippet.contains("pagar"))
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
    }

    @Test("sin coincidencia no hay resultado")
    func noMatchReturnsNothing() {
        let documents = [makeDocument(title: "Factura", searchText: "contenido irrelevante")]
        #expect(DocumentSearch.results(for: "inexistente", in: documents).isEmpty)
    }

    @Test("consulta vacía no devuelve resultados")
    func emptyQueryReturnsNothing() {
        let documents = [makeDocument(title: "Factura", searchText: "algo")]
        #expect(DocumentSearch.results(for: "", in: documents).isEmpty)
    }

    @Test("la búsqueda ignora mayúsculas y diacríticos")
    func isCaseAndDiacriticInsensitive() {
        let documents = [makeDocument(title: "Título", searchText: "número de referencia 123")]
        #expect(!DocumentSearch.results(for: "NUMERO", in: documents).isEmpty)
    }
}
