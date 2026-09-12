import Foundation

/// Contador mensual de páginas reconocidas del plan gratuito.
///
/// Aritmética pura: recibe estado y fecha, devuelve estado nuevo. No sabe de
/// `UserDefaults` ni del estado Pro —de eso se encarga `Entitlements`—, y por
/// eso se puede probar entera sin montar nada.
struct OCRQuota: Sendable, Equatable {

    /// Páginas reconocidas al mes sin pagar (`HANDOFF-Nitido.md` §11).
    static let freeMonthlyAllowance = 15

    /// Inicio del periodo en curso. **Nunca retrocede**, ni aunque el reloj del
    /// sistema lo haga.
    let periodStart: Date
    let used: Int

    init(periodStart: Date, used: Int) {
        self.periodStart = periodStart
        self.used = max(0, used)
    }

    /// Contador a estrenar, en el periodo que contiene `now`.
    init(startingAt now: Date, calendar: Calendar = .current) {
        self.init(periodStart: Self.periodStart(containing: now, calendar: calendar), used: 0)
    }

    var remaining: Int { max(0, Self.freeMonthlyAllowance - used) }

    var isExhausted: Bool { remaining == 0 }

    /// El contador puesto al día para `now`.
    ///
    /// Solo reinicia cuando el mes avanza de verdad. Si `now` cae antes del
    /// periodo guardado —el usuario ha retrasado la fecha del sistema para
    /// recuperar páginas gratis— se devuelve el contador intacto: ni se pone a
    /// cero, ni `periodStart` retrocede. Adelantar el reloj sí concede un
    /// reinicio, pero entonces `periodStart` queda en el futuro y volver atrás
    /// no concede otro. Sin red no hay reloj de confianza al que preguntar, así
    /// que cerrar del todo esa puerta no está a nuestro alcance; lo que sí se
    /// evita es el caso fácil y repetible.
    func rolledOver(to now: Date, calendar: Calendar = .current) -> OCRQuota {
        let current = Self.periodStart(containing: now, calendar: calendar)
        guard current > periodStart else { return self }
        return OCRQuota(periodStart: current, used: 0)
    }

    /// El contador con una página más consumida, o `nil` si no quedaba ninguna.
    ///
    /// Devolver un opcional en vez de un `Bool` aparte obliga a quien llama a
    /// mirar el resultado antes de reconocer nada.
    func consumed() -> OCRQuota? {
        guard !isExhausted else { return nil }
        return OCRQuota(periodStart: periodStart, used: used + 1)
    }

    /// Primer instante del mes natural que contiene `date`.
    static func periodStart(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
