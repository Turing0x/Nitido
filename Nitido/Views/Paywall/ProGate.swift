import SwiftUI

extension ProFeature: Identifiable {
    var id: Self { self }
}

/// Distintivo de los controles que no entran en el plan gratuito.
struct ProBadge: View {

    var body: some View {
        Text(String(localized: "pro.badge", defaultValue: "Pro"))
            .font(DS.Typography.scaled(DS.Typography.xs, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(DS.Brand.badgeAvailableFG)
            .padding(.horizontal, DS.Spacing.x2)
            .padding(.vertical, DS.Spacing.x1)
            .background(DS.Brand.badgeAvailableBG, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// Etiqueta de una fila, con el distintivo puesto solo cuando la función no
/// está disponible. Evita repetir el mismo `HStack` en las cuatro pantallas
/// donde hay un gate.
struct ProRowLabel: View {
    let title: String
    let isAllowed: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.x2) {
            Text(title)
            if !isAllowed { ProBadge() }
        }
    }
}

/// Bloquea un control y, al tocarlo, pide que se explique la función.
///
/// El control deshabilitado se esconde de VoiceOver y en su sitio queda un
/// botón transparente con la etiqueta de la función: así se puede tocar y se
/// anuncia bien, en vez de leerse como un control atenuado sin explicación.
private struct ProGateModifier: ViewModifier {
    let feature: ProFeature
    let isAllowed: Bool
    let onRequest: (ProFeature) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAllowed {
            content
        } else {
            content
                .disabled(true)
                .accessibilityHidden(true)
                .overlay {
                    Button {
                        onRequest(feature)
                    } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(feature.title)
                    .accessibilityHint(String(
                        localized: "pro.gate.hint",
                        defaultValue: "Función de Nítido Pro. Toca para saber qué hace."
                    ))
                }
        }
    }
}

/// Aviso de función de pago y hoja del paywall.
///
/// El paywall **no se abre solo**: primero se cuenta qué hace la función y solo
/// el botón explícito lo presenta. Quien solo estaba mirando las opciones sale
/// con un toque y sin que le hayan enseñado un precio que no pidió ver.
private struct ProFeatureNotice: ViewModifier {
    @Binding var requestedFeature: ProFeature?
    @State private var paywallFeature: ProFeature?

    func body(content: Content) -> some View {
        content
            .alert(
                requestedFeature?.title ?? "",
                isPresented: Binding(
                    get: { requestedFeature != nil },
                    set: { if !$0 { requestedFeature = nil } }
                ),
                presenting: requestedFeature
            ) { feature in
                Button(String(localized: "pro.gate.see", defaultValue: "Ver Nítido Pro")) {
                    paywallFeature = feature
                }
                Button(String(localized: "pro.gate.notNow", defaultValue: "Ahora no"), role: .cancel) {}
            } message: { feature in
                Text(feature.explanation)
            }
            .sheet(item: $paywallFeature) { feature in
                NavigationStack { PaywallView(highlighting: feature) }
            }
    }
}

extension View {

    /// Deja el control a la vista pero sin uso, y deriva el toque al aviso.
    func proGated(
        _ feature: ProFeature,
        isAllowed: Bool,
        onRequest: @escaping (ProFeature) -> Void
    ) -> some View {
        modifier(ProGateModifier(feature: feature, isAllowed: isAllowed, onRequest: onRequest))
    }

    /// Engancha el aviso y la hoja del paywall a una pantalla que tenga gates.
    func proFeatureNotice(_ requestedFeature: Binding<ProFeature?>) -> some View {
        modifier(ProFeatureNotice(requestedFeature: requestedFeature))
    }
}
