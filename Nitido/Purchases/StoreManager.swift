import Foundation
import StoreKit

/// Los dos productos de la app. El orden de `allCases` es el orden en que se
/// presentan en el paywall.
///
/// Estos identificadores tienen que coincidir a la letra con los de App Store
/// Connect y con los del fichero `Nitido.storekit`. Si se separan, los
/// productos no cargan y el paywall se queda vacío sin decir por qué.
enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "com.threedotsdev.nitido.pro.yearly"
    case lifetime = "com.threedotsdev.nitido.pro.lifetime"
}

/// Todo lo que toca StoreKit, y nada más.
///
/// Vive en el actor principal porque es estado de interfaz. No sabe qué
/// desbloquea Pro —eso es cosa de `Entitlements`—; solo sabe si está comprado.
@MainActor
@Observable
final class StoreManager {

    enum Phase: Equatable {
        case idle
        case loadingProducts
        case purchasing(productID: String)
        case restoring

        var isWorking: Bool { self != .idle }
    }

    private(set) var phase: Phase = .idle
    private(set) var products: [Product] = []

    /// Estado Pro. Se siembra con el valor cacheado en el `init` y se corrige
    /// en cuanto responden los derechos vigentes.
    private(set) var isPro: Bool

    /// El derecho viene de la compra vitalicia. Sirve para no ofrecerle una
    /// suscripción a quien ya pagó una vez y para siempre.
    private(set) var ownsLifetime = false

    /// Le corresponde la prueba de siete días. Quien ya la gastó no debe ver
    /// prometida una prueba que no va a recibir: eso es motivo de rechazo en
    /// App Review, además de una mentira.
    private(set) var isEligibleForTrial = true

    var errorMessage: String?

    private let defaults: UserDefaults
    private static let isProKey = "purchases.isPro"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Sin `await` y sin spinner: el arranque no espera a App Store.
        self.isPro = defaults.bool(forKey: Self.isProKey)
        observeTransactionUpdates()
    }

    // MARK: - Derechos

    /// Escucha permanente de `Transaction.updates`.
    ///
    /// Es la única vía por la que entran las compras hechas fuera de la app:
    /// otro dispositivo, la ficha de App Store, Compartir en familia o una
    /// renovación automática. Arranca en el `init` y no se cancela nunca a
    /// propósito —`StoreManager` se crea en `AppServices` y vive lo que vive el
    /// proceso—, que es justo lo que pide el handoff.
    private func observeTransactionUpdates() {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = Self.verified(result) else { continue }
                await self.refreshEntitlements()
                await transaction.finish()
            }
        }
    }

    /// Recalcula el estado Pro desde los derechos vigentes.
    ///
    /// `currentEntitlements` se sirve de la base de transacciones que el sistema
    /// mantiene en el dispositivo, así que responde igual en un avión que con
    /// cobertura: el usuario que compró sigue siendo Pro sin red. El valor
    /// cacheado no está aquí para suplir eso, sino para que el primer fotograma
    /// ya salga correcto sin esperar a esta enumeración.
    func refreshEntitlements() async {
        var entitled = false
        var lifetime = false
        for await result in Transaction.currentEntitlements {
            guard
                let transaction = Self.verified(result),
                let known = ProProduct(rawValue: transaction.productID),
                transaction.revocationDate == nil
            else { continue }
            entitled = true
            if known == .lifetime { lifetime = true }
        }
        ownsLifetime = lifetime
        apply(isPro: entitled)
    }

    private func apply(isPro value: Bool) {
        guard isPro != value else { return }
        isPro = value
        defaults.set(value, forKey: Self.isProKey)
    }

    /// Desenvuelve una transacción firmada por Apple.
    ///
    /// Una firma que no valida se descarta entera. No se registra ni se avisa:
    /// es el caso del dispositivo manipulado, y lo único correcto es tratarlo
    /// como si la compra no existiera.
    private static func verified(_ result: VerificationResult<Transaction>) -> Transaction? {
        switch result {
        case .verified(let transaction): transaction
        case .unverified: nil
        }
    }

    // MARK: - Catálogo

    func loadProducts() async {
        guard products.isEmpty else { return }

        phase = .loadingProducts
        defer { phase = .idle }

        do {
            let loaded = try await Product.products(for: ProProduct.allCases.map(\.rawValue))
            // Se reordenan según `ProProduct.allCases` en vez de fiarse del
            // orden en que los devuelva App Store, que no está garantizado.
            products = ProProduct.allCases.compactMap { known in
                loaded.first { $0.id == known.rawValue }
            }
            if products.isEmpty {
                errorMessage = String(
                    localized: "purchase.error.noProducts",
                    defaultValue: "Ahora mismo no se pueden cargar los planes. Vuelve a intentarlo en un rato."
                )
            }
            if let subscription = product(.yearly)?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        } catch {
            errorMessage = describe(error)
        }
    }

    func product(_ known: ProProduct) -> Product? {
        products.first { $0.id == known.rawValue }
    }

    // MARK: - Compra

    func purchase(_ product: Product) async {
        phase = .purchasing(productID: product.id)
        defer { phase = .idle }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard let transaction = Self.verified(verification) else {
                    errorMessage = String(
                        localized: "purchase.error.verification",
                        defaultValue: "La compra no se pudo verificar con App Store, así que no se ha activado nada. No se te ha cobrado."
                    )
                    return
                }
                await refreshEntitlements()
                await transaction.finish()

            case .userCancelled:
                // Salir del paywall no es un error y no merece un aviso.
                break

            case .pending:
                errorMessage = String(
                    localized: "purchase.error.pending",
                    defaultValue: "La compra está pendiente de aprobación. Se activará sola en cuanto se apruebe."
                )

            @unknown default:
                break
            }
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Restaurar compras. Siempre a petición explícita: `AppStore.sync()` pide
    /// la contraseña del ID de Apple y no se debe disparar solo.
    func restorePurchases() async {
        phase = .restoring
        defer { phase = .idle }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPro {
                errorMessage = String(
                    localized: "purchase.error.nothingToRestore",
                    defaultValue: "No hemos encontrado ninguna compra anterior con este ID de Apple."
                )
            }
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Privado

    /// Traduce los errores de StoreKit a algo que una persona pueda leer, o a
    /// `nil` cuando no hay nada que contar.
    ///
    /// `localizedDescription` del sistema aquí es técnico y a menudo sale en
    /// inglés. Mismo criterio que `ScanCoordinator.reportCameraError`.
    private func describe(_ error: Error) -> String? {
        if let storeKitError = error as? StoreKitError {
            switch storeKitError {
            case .networkError:
                return String(
                    localized: "purchase.error.network",
                    defaultValue: "No hay conexión con App Store. Inténtalo otra vez cuando vuelvas a tener red."
                )
            case .notAvailableInStorefront:
                return String(
                    localized: "purchase.error.storefront",
                    defaultValue: "Nítido Pro no está disponible en la tienda de tu país."
                )
            case .userCancelled:
                // Salir no es un error: no se avisa de nada.
                return nil
            default:
                break
            }
        }

        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return String(
                    localized: "purchase.error.unavailable",
                    defaultValue: "Este plan no está disponible ahora mismo."
                )
            case .purchaseNotAllowed:
                return String(
                    localized: "purchase.error.notAllowed",
                    defaultValue: "Este dispositivo no tiene permiso para hacer compras. Míralo en Ajustes, dentro de Tiempo de uso."
                )
            default:
                break
            }
        }

        return String(
            localized: "purchase.error.generic",
            defaultValue: "No se pudo completar la operación con App Store. Inténtalo de nuevo."
        )
    }
}
