import SwiftUI

/// Último recurso: la app no ha podido abrir ningún almacén, ni en disco ni en
/// memoria. No hay biblioteca que enseñar ni acción que ofrecer, pero sí un
/// mensaje que el usuario puede leer y transmitir.
struct StartupFailureView: View {
    let message: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "startup.failure.title", defaultValue: "Nítido no ha podido arrancar"),
                systemImage: "exclamationmark.triangle"
            )
            .font(DS.Typography.sectionTitle)
        } description: {
            VStack(spacing: DS.Spacing.x3) {
                Text(String(
                    localized: "startup.failure.description",
                    defaultValue: "No se pudo abrir el almacenamiento de la app. Prueba a reiniciar el iPhone; si el problema sigue, reinstalar Nítido lo soluciona, pero se perderán los documentos guardados."
                ))
                .font(DS.Typography.calloutText)

                if !message.isEmpty {
                    Text(message)
                        .font(DS.Typography.captionText)
                        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
                        .textSelection(.enabled)
                }
            }
        }
        .dsScreenBackground()
    }
}

#Preview {
    StartupFailureView(message: "The file “Nitido.store” couldn’t be opened.")
}
