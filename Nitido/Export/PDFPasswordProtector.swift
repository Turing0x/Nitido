import Foundation
import PDFKit

enum PDFPasswordProtectorError: Error {
    case invalidDocument
    case writeFailed
}

/// Reescribe un PDF ya generado con protección de contraseña. Una sola
/// contraseña visible hace de propietario y de usuario: es lo que espera
/// alguien no técnico al marcar "proteger con contraseña" — que haga falta
/// esa clave para abrir el fichero.
enum PDFPasswordProtector {
    static func protect(_ data: Data, password: String) throws -> Data {
        guard !password.isEmpty else { return data }
        guard let document = PDFDocument(data: data) else {
            throw PDFPasswordProtectorError.invalidDocument
        }

        // `PDFDocument.write(to:withOptions:)` aplica el cifrado de forma
        // fiable; la variante en memoria (`dataRepresentation(options:)`) no
        // lo hace siempre. Por eso se hace el viaje por un fichero temporal.
        let outputURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf", directoryHint: .notDirectory)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: password,
            .userPasswordOption: password
        ]
        guard document.write(to: outputURL, withOptions: options) else {
            throw PDFPasswordProtectorError.writeFailed
        }
        return try Data(contentsOf: outputURL)
    }
}
