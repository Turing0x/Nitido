import Foundation
import PDFKit

enum PDFPasswordProtectorError: Error, LocalizedError, Equatable {
    case invalidDocument
    case writeFailed
    case emptyPassword

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            String(localized: "export.password.error.invalidDocument",
                   defaultValue: "No se pudo preparar el PDF para protegerlo.")
        case .writeFailed:
            String(localized: "export.password.error.writeFailed",
                   defaultValue: "No se pudo cifrar el PDF.")
        case .emptyPassword:
            String(localized: "export.password.error.empty",
                   defaultValue: "Escribe una contraseña para proteger el PDF, o desactiva la protección.")
        }
    }
}

/// Reescribe un PDF ya generado con protección de contraseña. Una sola
/// contraseña visible hace de propietario y de usuario: es lo que espera
/// alguien no técnico al marcar "proteger con contraseña" — que haga falta
/// esa clave para abrir el fichero.
enum PDFPasswordProtector {

    /// - Parameter password: `nil` cuando no se ha pedido protección. Una
    ///   cadena **vacía** es un error, no un "no protejas": antes esta función
    ///   devolvía el PDF sin cifrar ante una contraseña vacía, así que marcar
    ///   la casilla y dejar el campo en blanco producía un fichero desprotegido
    ///   que el usuario creía seguro. Un documento sin cifrar nunca debe salir
    ///   de aquí por un descuido de quien llama.
    static func protect(_ data: Data, password: String?) throws -> Data {
        guard let password else { return data }
        guard !password.isEmpty else { throw PDFPasswordProtectorError.emptyPassword }
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

        // Comprobación final: si por lo que sea el fichero escrito no está
        // cifrado, es preferible fallar la exportación que entregar un PDF
        // abierto a quien pidió uno protegido.
        let written = try Data(contentsOf: outputURL)
        guard PDFDocument(data: written)?.isEncrypted == true else {
            throw PDFPasswordProtectorError.writeFailed
        }
        return written
    }
}
