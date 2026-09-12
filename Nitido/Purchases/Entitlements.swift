import Foundation

/// Las cinco funciones de pago, tal y como están fijadas en
/// `HANDOFF-Nitido.md` §11. No hay más, y no se añaden sobre la marcha.
enum ProFeature: Sendable, CaseIterable {
    case unlimitedOCR
    case searchablePDF
    case pdfPassword
    case batchExport
    case manualOCRLanguage
}

extension ProFeature {

    var title: String {
        switch self {
        case .unlimitedOCR:
            String(localized: "pro.feature.unlimitedOCR.title",
                   defaultValue: "Reconocimiento de texto sin límite")
        case .searchablePDF:
            String(localized: "pro.feature.searchablePDF.title",
                   defaultValue: "PDF con texto buscable")
        case .pdfPassword:
            String(localized: "pro.feature.pdfPassword.title",
                   defaultValue: "PDF protegido con contraseña")
        case .batchExport:
            String(localized: "pro.feature.batchExport.title",
                   defaultValue: "Exportar varios documentos a la vez")
        case .manualOCRLanguage:
            String(localized: "pro.feature.manualOCRLanguage.title",
                   defaultValue: "Elegir el idioma del reconocimiento")
        }
    }

    /// Lo que se le cuenta a quien toca la función sin tenerla. Explica qué
    /// hace, no por qué debería pagar.
    var explanation: String {
        switch self {
        case .unlimitedOCR:
            String(localized: "pro.feature.unlimitedOCR.explanation",
                   defaultValue: "Reconoce el texto de todas las páginas que quieras. El plan gratuito reconoce quince al mes.")
        case .searchablePDF:
            String(localized: "pro.feature.searchablePDF.explanation",
                   defaultValue: "El PDF lleva dentro el texto reconocido, invisible y colocado sobre la imagen. Se puede buscar y seleccionar como si fuera un documento escrito, también desde el ordenador.")
        case .pdfPassword:
            String(localized: "pro.feature.pdfPassword.explanation",
                   defaultValue: "Pon una contraseña al PDF antes de compartirlo. Quien no la tenga no puede abrirlo.")
        case .batchExport:
            String(localized: "pro.feature.batchExport.explanation",
                   defaultValue: "Selecciona varios documentos y expórtalos todos de una vez, en lugar de ir uno por uno.")
        case .manualOCRLanguage:
            String(localized: "pro.feature.manualOCRLanguage.explanation",
                   defaultValue: "Fija el idioma del reconocimiento en vez de dejar que se detecte solo. Se nota en documentos cortos y en los que mezclan dos idiomas.")
        }
    }
}

/// Quién sabe si hay Pro comprado.
///
/// Existe para que `Entitlements` —donde está toda la lógica de gates, que es
/// lo que de verdad hay que probar— no arrastre StoreKit dentro de los tests.
/// Mismo reparto que `FileStoring` y `LocalFileStore`.
@MainActor
protocol ProStateProviding: AnyObject {
    var isPro: Bool { get }
}

extension StoreManager: ProStateProviding {}

/// El único sitio de la app que decide si algo está permitido.
///
/// Las vistas preguntan aquí; ninguna mira `StoreManager` ni `UserDefaults` por
/// su cuenta. Eso es lo que permite cambiar el reparto entre gratis y Pro
/// tocando un fichero, y lo que evita que un gate se quede olvidado a medias en
/// una pantalla.
@MainActor
@Observable
final class Entitlements {

    private let proState: any ProStateProviding
    private let defaults: UserDefaults
    /// Inyectable para poder probar el paso de mes sin tocar el reloj real.
    private let now: @Sendable () -> Date

    private static let periodStartKey = "ocr.quota.periodStart"
    private static let usedKey = "ocr.quota.used"

    private(set) var quota: OCRQuota

    init(
        storeManager: any ProStateProviding,
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.proState = storeManager
        self.defaults = defaults
        self.now = now
        self.quota = Self.loadQuota(from: defaults, now: now())
    }

    var isPro: Bool { proState.isPro }

    func allows(_ feature: ProFeature) -> Bool { isPro }

    // MARK: - Cuota de reconocimiento

    /// Páginas que le quedan al plan gratuito este mes. Sin sentido para Pro.
    var remainingFreeOCRPages: Int { quota.remaining }

    var hasExhaustedFreeOCR: Bool { !isPro && quota.isExhausted }

    /// ¿Se puede reconocer esta página ahora mismo? Consume cuota si procede.
    ///
    /// `alreadyCounted` viene de la propia página: si ya gastó su unidad en su
    /// día, vuelve a pasar gratis. Eso es lo que hace que reintentar un
    /// reconocimiento fallido, o recortar una página y tener que rehacer las
    /// cajas, no le cueste el mes a nadie.
    ///
    /// Se llama desde el actor principal, una página cada vez, así que el
    /// consumo queda serializado sin necesidad de más cerrojos.
    func permitOCR(alreadyCounted: Bool) -> Bool {
        if isPro || alreadyCounted { return true }

        refreshPeriod()
        guard let consumed = quota.consumed() else { return false }
        quota = consumed
        persistQuota()
        return true
    }

    /// Pone el periodo al día. Se llama sola antes de consumir, y desde la
    /// pantalla de Ajustes para que el contador no se vea rancio si la app
    /// lleva abierta desde el mes pasado.
    func refreshPeriod() {
        let rolled = quota.rolledOver(to: now())
        guard rolled != quota else { return }
        quota = rolled
        persistQuota()
    }

    // MARK: - Privado

    private static func loadQuota(from defaults: UserDefaults, now: Date) -> OCRQuota {
        guard let storedStart = defaults.object(forKey: periodStartKey) as? Date else {
            return OCRQuota(startingAt: now)
        }
        return OCRQuota(periodStart: storedStart, used: defaults.integer(forKey: usedKey))
            .rolledOver(to: now)
    }

    private func persistQuota() {
        defaults.set(quota.periodStart, forKey: Self.periodStartKey)
        defaults.set(quota.used, forKey: Self.usedKey)
    }
}
