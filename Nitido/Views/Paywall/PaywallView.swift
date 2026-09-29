import StoreKit
import SwiftUI

/// Enlaces legales del paywall.
///
/// App Review exige los dos en cualquier pantalla con suscripción
/// auto-renovable, y los rechaza si no llevan a ninguna parte.
enum LegalLinks {
    static let termsOfUse = URL(string: "https://apps.threedotsdev.com/terms/nitido")
    static let privacyPolicy = URL(string: "https://apps.threedotsdev.com/privacy/nitido")
}

struct PaywallView: View {

    /// Función desde la que se llegó, cuando se llega desde un gate. Sirve para
    /// contestar arriba del todo a la pregunta que trae al usuario aquí.
    var highlighting: ProFeature?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.x6) {
                header
                if let highlighting {
                    highlightCard(highlighting)
                }
                featureList
                plans
                renewalTerms
                restoreButton
                legalLinks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.screenGutter)
            .padding(.vertical, DS.Spacing.x6)
        }
        .background {
            DS.ColorToken.background(scheme)
                .overlay(DS.Brand.glow)
                .ignoresSafeArea()
        }
        .navigationTitle(String(localized: "paywall.title", defaultValue: "Nítido Pro"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.close", defaultValue: "Cerrar")) { dismiss() }
            }
        }
        .task { await store.loadProducts() }
        .alert(
            String(localized: "purchase.error.title", defaultValue: "No se pudo completar"),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok", defaultValue: "Aceptar"), role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            Text(String(localized: "paywall.eyebrow", defaultValue: "Todo en tu iPhone"))
                .dsEyebrow()
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))

            Text(String(localized: "paywall.headline", defaultValue: "Nítido Pro"))
                .font(DS.Typography.screenTitle)
                .foregroundStyle(DS.ColorToken.foreground(scheme))

            Text(String(
                localized: "paywall.subheadline",
                defaultValue: "Sin cuenta, sin anuncios y sin que tus documentos salgan del dispositivo. Lo único que cambia es que se quitan los límites."
            ))
            .font(DS.Typography.bodyText)
            .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
    }

    private func highlightCard(_ feature: ProFeature) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            Text(feature.title)
                .font(DS.Typography.rowTitle)
                .foregroundStyle(DS.ColorToken.foreground(scheme))
            Text(feature.explanation)
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(scheme)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x3) {
            ForEach(ProFeature.allCases) { feature in
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.x3) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.ColorToken.primary(scheme))
                        .accessibilityHidden(true)
                    Text(feature.title)
                        .font(DS.Typography.bodyText)
                        .foregroundStyle(DS.ColorToken.foreground(scheme))
                }
            }
        }
    }

    // MARK: - Planes

    @ViewBuilder
    private var plans: some View {
        if store.isPro {
            activeState
        } else if store.products.isEmpty {
            unavailablePlans
        } else {
            VStack(spacing: DS.Spacing.x3) {
                if let yearly = store.product(.yearly) {
                    planButton(
                        for: yearly,
                        caption: yearlyCaption(for: yearly),
                        isRecommended: true
                    )
                }
                if let lifetime = store.product(.lifetime) {
                    planButton(
                        for: lifetime,
                        caption: String(
                            localized: "paywall.lifetime.caption",
                            defaultValue: "\(lifetime.displayPrice), un solo pago"
                        ),
                        isRecommended: false
                    )
                }
            }
        }
    }

    private var activeState: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            Label(
                String(localized: "paywall.active.title", defaultValue: "Ya tienes Nítido Pro"),
                systemImage: "checkmark.seal.fill"
            )
            .font(DS.Typography.rowTitle)
            .foregroundStyle(DS.ColorToken.primary(scheme))

            Text(store.ownsLifetime
                 ? String(localized: "paywall.active.lifetime",
                          defaultValue: "Lo compraste para siempre. No hay nada que renovar ni que cancelar.")
                 : String(localized: "paywall.active.subscription",
                          defaultValue: "Puedes gestionar o cancelar la suscripción en Ajustes de iOS, dentro de tu cuenta de App Store."))
                .font(DS.Typography.calloutText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(scheme)
    }

    @ViewBuilder
    private var unavailablePlans: some View {
        if store.phase == .loadingProducts {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DS.Spacing.x6)
        } else {
            Button(String(localized: "paywall.retry", defaultValue: "Volver a cargar los planes")) {
                Task { await store.loadProducts() }
            }
            .buttonStyle(DSPrimaryButtonStyle())
        }
    }

    /// "7 días gratis, luego 12,99 € al año", o solo el precio si la prueba ya
    /// se gastó en su día.
    private func yearlyCaption(for product: Product) -> String {
        guard
            store.isEligibleForTrial,
            let offer = product.subscription?.introductoryOffer,
            offer.paymentMode == .freeTrial
        else {
            return String(
                localized: "paywall.yearly.caption",
                defaultValue: "\(product.displayPrice) al año"
            )
        }
        return String(
            localized: "paywall.yearly.trial",
            defaultValue: "\(Self.days(in: offer.period)) días gratis, luego \(product.displayPrice) al año"
        )
    }

    /// La prueba se configura en semanas, pero "7 días" es como lo cuenta la
    /// gente y como lo pide la ficha de App Store.
    private static func days(in period: Product.SubscriptionPeriod) -> Int {
        switch period.unit {
        case .day: period.value
        case .week: period.value * 7
        case .month: period.value * 30
        case .year: period.value * 365
        @unknown default: period.value
        }
    }

    private func planButton(for product: Product, caption: String, isRecommended: Bool) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            planLabel(for: product, caption: caption, isRecommended: isRecommended)
        }
        .buttonStyle(.plain)
        .disabled(store.phase.isWorking)
        .accessibilityLabel("\(product.displayName). \(caption)")
    }

    @ViewBuilder
    private func planLabel(for product: Product, caption: String, isRecommended: Bool) -> some View {
        let isBuyingThis = store.phase == .purchasing(productID: product.id)

        VStack(spacing: DS.Spacing.x1) {
            HStack(spacing: DS.Spacing.x2) {
                Text(product.displayName)
                    .font(DS.Typography.scaled(DS.Typography.base, weight: .semibold, relativeTo: .body))
                if isBuyingThis {
                    ProgressView().controlSize(.small)
                }
            }
            Text(caption)
                .font(DS.Typography.calloutText)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.vertical, DS.Spacing.x2)
        .foregroundStyle(isRecommended ? DS.Brand.ctaPrimaryFG : DS.ColorToken.foreground(scheme))
        .background(isRecommended ? DS.ColorToken.primary(scheme) : DS.ColorToken.muted(scheme))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.ColorToken.border(scheme), lineWidth: isRecommended ? 0 : DS.Border.hairline)
        }
    }

    // MARK: - Condiciones y salidas

    private var renewalTerms: some View {
        Text(String(
            localized: "paywall.renewalTerms",
            defaultValue: "La suscripción anual se renueva sola cada año hasta que la canceles. Si empiezas con la prueba gratuita, se cobra el primer año al terminar los siete días, salvo que canceles antes. Puedes cancelar cuando quieras desde Ajustes de iOS, en tu cuenta de App Store, y basta con hacerlo al menos 24 horas antes de que acabe el periodo en curso. La compra de por vida es un pago único y no se renueva nunca."
        ))
        .font(DS.Typography.captionText)
        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
    }

    private var restoreButton: some View {
        Button {
            Task { await store.restorePurchases() }
        } label: {
            HStack(spacing: DS.Spacing.x2) {
                Text(String(localized: "paywall.restore", defaultValue: "Restaurar compras"))
                if store.phase == .restoring {
                    ProgressView().controlSize(.small)
                }
            }
            .font(DS.Typography.rowTitle)
            .foregroundStyle(DS.ColorToken.primary(scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(store.phase.isWorking)
    }

    private var legalLinks: some View {
        HStack(spacing: DS.Spacing.x4) {
            if let terms = LegalLinks.termsOfUse {
                Link(String(localized: "paywall.terms", defaultValue: "Términos de uso"), destination: terms)
            }
            if let privacy = LegalLinks.privacyPolicy {
                Link(String(localized: "paywall.privacy", defaultValue: "Política de privacidad"), destination: privacy)
            }
        }
        .font(DS.Typography.captionText)
        .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    NavigationStack { PaywallView() }
        .environment(StoreManager())
}
