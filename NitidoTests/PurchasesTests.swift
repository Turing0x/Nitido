import Foundation
import SwiftData
import Testing
@testable import Nitido

@Suite("Cuota de OCR")
struct OCRQuotaTests {

    /// Gregoriano y en GMT: las pruebas no deben cambiar de resultado según
    /// dónde esté la máquina que las ejecuta.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        return try #require(calendar.date(from: components))
    }

    private func periodStart(_ year: Int, _ month: Int) throws -> Date {
        OCRQuota.periodStart(containing: try date(year, month, 1), calendar: calendar)
    }

    @Test("un contador nuevo trae las quince páginas del mes")
    func startsWithFullAllowance() throws {
        let quota = OCRQuota(startingAt: try date(2026, 3, 10), calendar: calendar)

        #expect(quota.remaining == 15)
        #expect(!quota.isExhausted)
    }

    @Test("consumir una página descuenta del restante y respeta el periodo")
    func consumingDecrements() throws {
        let quota = OCRQuota(startingAt: try date(2026, 3, 10), calendar: calendar)

        let next = try #require(quota.consumed())

        #expect(next.remaining == 14)
        #expect(next.periodStart == quota.periodStart)
    }

    @Test("el contador se agota justo a las quince páginas")
    func exhaustsAtFifteen() throws {
        var quota = OCRQuota(startingAt: try date(2026, 3, 10), calendar: calendar)

        for _ in 0..<OCRQuota.freeMonthlyAllowance {
            quota = try #require(quota.consumed())
        }

        #expect(quota.isExhausted)
        #expect(quota.remaining == 0)
        #expect(quota.consumed() == nil)
    }

    @Test("el mes siguiente reinicia el contador")
    func rollsOverOnNewMonth() throws {
        let march = OCRQuota(periodStart: try periodStart(2026, 3), used: 15)

        let april = march.rolledOver(to: try date(2026, 4, 2), calendar: calendar)

        #expect(april.used == 0)
        #expect(april.remaining == 15)
        #expect(april.periodStart == (try periodStart(2026, 4)))
    }

    @Test("dentro del mismo mes el contador no se toca")
    func keepsCountWithinMonth() throws {
        let quota = OCRQuota(periodStart: try periodStart(2026, 3), used: 7)

        let later = quota.rolledOver(to: try date(2026, 3, 28), calendar: calendar)

        #expect(later == quota)
    }

    @Test("retrasar el reloj del sistema no devuelve páginas gratis")
    func ignoresClockGoingBackwards() throws {
        let march = try periodStart(2026, 3)
        let exhausted = OCRQuota(periodStart: march, used: 15)

        let tampered = exhausted.rolledOver(to: try date(2026, 1, 5), calendar: calendar)

        #expect(tampered.used == 15)
        #expect(tampered.isExhausted)
        #expect(tampered.periodStart == march, "el periodo no debe retroceder")
    }

    @Test("saltar varios meses hacia delante reinicia una sola vez")
    func rollsOverOnceAcrossManyMonths() throws {
        let january = OCRQuota(periodStart: try periodStart(2026, 1), used: 15)

        let june = january.rolledOver(to: try date(2026, 6, 20), calendar: calendar)

        #expect(june.used == 0)
        #expect(june.periodStart == (try periodStart(2026, 6)))
    }
}

/// Fecha fija para las pruebas de `Entitlements`. Se evita el día 1 a
/// propósito: a mediodía en GMT, cualquier día del 2 en adelante cae en el
/// mismo mes en todos los husos horarios, y así el resultado no depende de
/// dónde se ejecuten las pruebas.
private func testDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
}

@MainActor
@Suite("Gates de Nítido Pro")
struct EntitlementsTests {

    /// Doble de `StoreManager`: los gates se prueban sin levantar StoreKit.
    @MainActor
    private final class ProStateStub: ProStateProviding {
        var isPro: Bool
        init(isPro: Bool) { self.isPro = isPro }
    }

    /// Dominio propio por prueba. `UserDefaults.standard` es global y las
    /// pruebas se pisarían entre ellas y con la app.
    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "test.purchases.\(UUID().uuidString)"))
    }

    private func makeEntitlements(
        isPro: Bool,
        defaults: UserDefaults,
        now: Date = testDate(2026, 3, 10)
    ) -> Entitlements {
        Entitlements(storeManager: ProStateStub(isPro: isPro), defaults: defaults, now: { now })
    }

    @Test("sin Pro no está permitida ninguna función de pago")
    func deniesEveryFeatureWhenFree() throws {
        let entitlements = makeEntitlements(isPro: false, defaults: try makeDefaults())

        for feature in ProFeature.allCases {
            #expect(!entitlements.allows(feature), "\(feature) no debería estar permitida")
        }
    }

    @Test("con Pro están permitidas todas")
    func allowsEveryFeatureWhenPro() throws {
        let entitlements = makeEntitlements(isPro: true, defaults: try makeDefaults())

        for feature in ProFeature.allCases {
            #expect(entitlements.allows(feature), "\(feature) debería estar permitida")
        }
    }

    @Test("el plan gratuito reconoce quince páginas y ni una más")
    func stopsAtTheFreeAllowance() throws {
        let entitlements = makeEntitlements(isPro: false, defaults: try makeDefaults())

        for _ in 0..<OCRQuota.freeMonthlyAllowance {
            #expect(entitlements.permitOCR(alreadyCounted: false))
        }

        #expect(!entitlements.permitOCR(alreadyCounted: false))
        #expect(entitlements.remainingFreeOCRPages == 0)
        #expect(entitlements.hasExhaustedFreeOCR)
    }

    @Test("una página ya contada no vuelve a gastar cuota")
    func alreadyCountedPagesAreFree() throws {
        let entitlements = makeEntitlements(isPro: false, defaults: try makeDefaults())

        #expect(entitlements.permitOCR(alreadyCounted: true))

        #expect(entitlements.remainingFreeOCRPages == OCRQuota.freeMonthlyAllowance)
    }

    @Test("reintentar una página ya contada funciona con la cuota agotada")
    func retryingCountedPageSurvivesExhaustion() throws {
        let entitlements = makeEntitlements(isPro: false, defaults: try makeDefaults())
        for _ in 0..<OCRQuota.freeMonthlyAllowance {
            _ = entitlements.permitOCR(alreadyCounted: false)
        }

        #expect(entitlements.permitOCR(alreadyCounted: true))
    }

    @Test("Pro no gasta cuota")
    func proDoesNotConsume() throws {
        let entitlements = makeEntitlements(isPro: true, defaults: try makeDefaults())

        for _ in 0..<40 {
            #expect(entitlements.permitOCR(alreadyCounted: false))
        }

        #expect(entitlements.remainingFreeOCRPages == OCRQuota.freeMonthlyAllowance)
        #expect(!entitlements.hasExhaustedFreeOCR)
    }

    @Test("la cuota gastada sobrevive a cerrar y reabrir la app")
    func quotaPersistsAcrossLaunches() throws {
        let defaults = try makeDefaults()
        let first = makeEntitlements(isPro: false, defaults: defaults)
        for _ in 0..<4 {
            _ = first.permitOCR(alreadyCounted: false)
        }

        let second = makeEntitlements(isPro: false, defaults: defaults)

        #expect(second.remainingFreeOCRPages == 11)
    }

    @Test("el mes nuevo devuelve las quince páginas")
    func newMonthRestoresAllowance() throws {
        let defaults = try makeDefaults()
        let march = makeEntitlements(isPro: false, defaults: defaults, now: testDate(2026, 3, 10))
        for _ in 0..<OCRQuota.freeMonthlyAllowance {
            _ = march.permitOCR(alreadyCounted: false)
        }
        #expect(march.hasExhaustedFreeOCR)

        let april = makeEntitlements(isPro: false, defaults: defaults, now: testDate(2026, 4, 5))

        #expect(april.remainingFreeOCRPages == OCRQuota.freeMonthlyAllowance)
    }

    @Test("retrasar el reloj no devuelve páginas al plan gratuito")
    func clockTamperingDoesNotRestoreAllowance() throws {
        let defaults = try makeDefaults()
        let march = makeEntitlements(isPro: false, defaults: defaults, now: testDate(2026, 3, 10))
        for _ in 0..<OCRQuota.freeMonthlyAllowance {
            _ = march.permitOCR(alreadyCounted: false)
        }

        let tampered = makeEntitlements(isPro: false, defaults: defaults, now: testDate(2026, 1, 5))

        #expect(tampered.remainingFreeOCRPages == 0)
        #expect(!tampered.permitOCR(alreadyCounted: false))
    }
}

@Suite("Cuota en el almacén")
struct QuotaStorageTests {

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

    @Test("el primer reconocimiento marca la página como contada")
    func recognitionMarksPageAsCounted() async throws {
        let store = DocumentStore(modelContainer: try ModelContainer.nitidoInMemory())
        let records = makeRecords(1)
        let documentID = try await store.createDocument(title: "Factura", records: records)
        let pageID = records[0].pageID

        let before = try await store.ocrPageInfo(pageID: pageID, in: documentID)
        #expect(!before.ocrCounted)

        try await store.setOCRResult(
            PageOCRUpdate(pageID: pageID, text: "importe total", boxes: []),
            in: documentID
        )

        let after = try await store.ocrPageInfo(pageID: pageID, in: documentID)
        #expect(after.ocrCounted)
    }

    @Test("las páginas aplazadas se pueden localizar para reanudarlas")
    func deferredPagesAreDiscoverable() async throws {
        let store = DocumentStore(modelContainer: try ModelContainer.nitidoInMemory())
        let records = makeRecords(3)
        let documentID = try await store.createDocument(title: "Contrato", records: records)

        try await store.setOCRDeferred(records[1].pageID, in: documentID)
        try await store.setOCRDeferred(records[2].pageID, in: documentID)

        let pending = try await store.deferredOCRPages()
        let count = try await store.deferredOCRPageCount()

        #expect(pending[documentID] == [records[1].pageID, records[2].pageID])
        #expect(count == 2)
    }

    @Test("reconocer una página aplazada la saca de la lista de pendientes")
    func recognitionClearsDeferral() async throws {
        let store = DocumentStore(modelContainer: try ModelContainer.nitidoInMemory())
        let records = makeRecords(1)
        let documentID = try await store.createDocument(title: "Nómina", records: records)
        let pageID = records[0].pageID
        try await store.setOCRDeferred(pageID, in: documentID)

        try await store.setOCRResult(
            PageOCRUpdate(pageID: pageID, text: "bruto anual", boxes: []),
            in: documentID
        )

        let count = try await store.deferredOCRPageCount()
        #expect(count == 0)
    }

    @Test("un fallo de reconocimiento no se confunde con una página sin cuota")
    func failureIsNotDeferral() async throws {
        let store = DocumentStore(modelContainer: try ModelContainer.nitidoInMemory())
        let records = makeRecords(1)
        let documentID = try await store.createDocument(title: "Recibo", records: records)
        let pageID = records[0].pageID
        try await store.setOCRDeferred(pageID, in: documentID)

        try await store.setOCRFailed(pageID, in: documentID)

        let count = try await store.deferredOCRPageCount()
        #expect(count == 0, "un fallo deja la página lista para reintentar a mano, no esperando cuota")
    }
}
