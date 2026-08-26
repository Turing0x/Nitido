//
//  DesignTokens.swift
//  ThreeDotsDev — Escáner de documentos
//
//  Tokens generados desde _ds/threedotsdev-design-system-.../colors_and_type.css
//  Fuente única de verdad: si cambia el CSS, se regenera este archivo.
//  Modo por defecto: oscuro (la app del escáner corre en dark).
//

import SwiftUI

// MARK: - Color helpers

extension Color {
    /// Color desde HSL (los tokens de shadcn/ui se definen en HSL).
    init(h: Double, s: Double, l: Double, opacity: Double = 1) {
        let hue = h / 360
        let sat = s / 100
        let lig = l / 100
        let a = sat * min(lig, 1 - lig)
        func f(_ n: Double) -> Double {
            let k = (n + hue * 12).truncatingRemainder(dividingBy: 12)
            return lig - a * max(-1, min(min(k - 3, 9 - k), 1))
        }
        self.init(.sRGB, red: f(0), green: f(8), blue: f(4), opacity: opacity)
    }

    /// Color desde hex (#RRGGBB o #RRGGBBAA).
    init(hex: String, opacity: Double? = nil) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let hasAlpha = s.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity ?? a)
    }
}

// MARK: - Tokens

public enum DS {

    // MARK: Semantic color (shadcn/ui token layer)

    public enum ColorToken {

        // ---- Dark (modo por defecto de la app) ----
        public enum Dark {
            public static let background         = Color(h: 240, s: 10,  l: 3.9)
            public static let foreground         = Color(h: 0,   s: 0,   l: 98)
            public static let card               = Color(h: 240, s: 10,  l: 3.9)
            public static let cardForeground     = Color(h: 0,   s: 0,   l: 98)
            public static let popover            = Color(h: 240, s: 10,  l: 3.9)
            public static let popoverForeground  = Color(h: 0,   s: 0,   l: 98)
            public static let primary            = Color(h: 152, s: 76,  l: 44)   // emerald-400
            public static let primaryForeground  = Color(h: 0,   s: 0,   l: 0)
            public static let secondary          = Color(h: 240, s: 3.7, l: 15.9)
            public static let secondaryForeground = Color(h: 0,  s: 0,   l: 98)
            public static let muted              = Color(h: 240, s: 3.7, l: 15.9)
            public static let mutedForeground    = Color(h: 240, s: 5,   l: 64.9)
            public static let accent             = Color(h: 240, s: 3.7, l: 15.9)
            public static let accentForeground   = Color(h: 0,   s: 0,   l: 98)
            public static let destructive         = Color(h: 0,  s: 62.8, l: 30.6)
            public static let destructiveForeground = Color(h: 0, s: 0,  l: 98)
            public static let border             = Color(h: 240, s: 3.7, l: 15.9)
            public static let input              = Color(h: 240, s: 3.7, l: 15.9)
            public static let ring               = Color(h: 152, s: 76,  l: 44)
        }

        // ---- Light (par claro, poco usado) ----
        public enum Light {
            public static let background         = Color(h: 0,   s: 0,   l: 100)
            public static let foreground         = Color(h: 240, s: 10,  l: 3.9)
            public static let card               = Color(h: 0,   s: 0,   l: 100)
            public static let cardForeground     = Color(h: 240, s: 10,  l: 3.9)
            public static let popover            = Color(h: 0,   s: 0,   l: 100)
            public static let popoverForeground  = Color(h: 240, s: 10,  l: 3.9)
            public static let primary            = Color(h: 160, s: 84,  l: 39)   // emerald-500
            public static let primaryForeground  = Color(h: 0,   s: 0,   l: 0)
            public static let secondary          = Color(h: 240, s: 4.8, l: 95.9)
            public static let secondaryForeground = Color(h: 240, s: 5.9, l: 10)
            public static let muted              = Color(h: 240, s: 4.8, l: 95.9)
            public static let mutedForeground    = Color(h: 240, s: 3.8, l: 46.1)
            public static let accent             = Color(h: 240, s: 4.8, l: 95.9)
            public static let accentForeground   = Color(h: 240, s: 5.9, l: 10)
            public static let destructive         = Color(h: 0,  s: 84,  l: 60)
            public static let destructiveForeground = Color(h: 0, s: 0,  l: 98)
            public static let border             = Color(h: 240, s: 5.9, l: 90)
            public static let input              = Color(h: 240, s: 5.9, l: 90)
            public static let ring               = Color(h: 160, s: 84,  l: 39)
        }

        /// Resuelve el token según el esquema de color actual.
        public static func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.background : Light.background }
        public static func foreground(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.foreground : Light.foreground }
        public static func card(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.card : Light.card }
        public static func primary(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.primary : Light.primary }
        public static func muted(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.muted : Light.muted }
        public static func mutedForeground(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.mutedForeground : Light.mutedForeground }
        public static func border(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.border : Light.border }
        public static func destructive(_ scheme: ColorScheme) -> Color { scheme == .dark ? Dark.destructive : Light.destructive }
    }

    // MARK: Brand palette (wordmark + acentos focales)

    public enum Brand {
        public static let dotCyanFrom   = Color(hex: "#22d3ee")
        public static let dotCyanTo     = Color(hex: "#2563eb")
        public static let dotGreenFrom  = Color(hex: "#4ade80")
        public static let dotGreenTo    = Color(hex: "#059669")
        public static let dotOrangeFrom = Color(hex: "#fb923c")
        public static let dotOrangeTo   = Color(hex: "#dc2626")

        /// Degradado del wordmark: emerald → cyan → emerald, 90°.
        public static let wordmark = LinearGradient(
            colors: [Color(hex: "#4ade80"), Color(hex: "#22d3ee"), Color(hex: "#10b981")],
            startPoint: .leading, endPoint: .trailing
        )

        /// Resplandor de fondo (radial emerald, arriba y centrado).
        public static let glow = RadialGradient(
            colors: [Color(hex: "#10b981").opacity(0.12), .clear],
            center: UnitPoint(x: 0.5, y: -0.15), startRadius: 0, endRadius: 600
        )

        /// Rejilla de fondo: hairlines blancas al 6 %, celda de 60 pt.
        public static let gridLine = Color.white.opacity(0.06)
        public static let gridSize: CGFloat = 60

        // Badge de disponibilidad
        public static let badgeAvailableBG = Color(hex: "#10b981").opacity(0.15)
        public static let badgeAvailableFG = Color(hex: "#6ee7b7")

        // CTA
        public static let ctaPrimaryBG        = Color(hex: "#10b981")
        public static let ctaPrimaryBGHover   = Color(hex: "#34d399")
        public static let ctaPrimaryFG        = Color(hex: "#000000")
        public static let ctaSecondaryBG      = Color(hex: "#1e40af")
        public static let ctaSecondaryBGHover = Color(hex: "#2563eb")
        public static let ctaSecondaryFG      = Color(hex: "#ffffff")
    }

    // MARK: Typography

    public enum Typography {
        /// Geist es la familia del sitio; Inter es el fallback empaquetado.
        public static let sans = "Geist"
        public static let sansFallback = "Inter"
        public static let mono = "Geist Mono"

        // Escala equivalente a Tailwind (pt = px)
        public static let xs: CGFloat   = 12
        public static let sm: CGFloat   = 14
        public static let base: CGFloat = 16
        public static let lg: CGFloat   = 18
        public static let xl: CGFloat   = 20
        public static let xl2: CGFloat  = 24
        public static let xl3: CGFloat  = 30
        public static let xl4: CGFloat  = 36
        public static let xl5: CGFloat  = 48
        public static let xl6: CGFloat  = 60

        // Line height
        public static let leadingXS: CGFloat   = 16
        public static let leadingSM: CGFloat   = 20
        public static let leadingBase: CGFloat = 24
        public static let leadingLG: CGFloat   = 28
        public static let leadingTight: CGFloat = 1.2

        // Tracking (em → se aplica con .tracking(size * value))
        public static let trackingTighter: CGFloat = -0.05
        public static let trackingTight: CGFloat   = -0.025
        public static let trackingNormal: CGFloat  = 0
        public static let trackingWide: CGFloat    = 0.025

        /// Fuente del sistema con fallback si Geist/Inter no están instaladas.
        public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if UIFont(name: sans, size: size) != nil {
                return .custom(sans, size: size)
            }
            if UIFont(name: sansFallback, size: size) != nil {
                return .custom(sansFallback, size: size)
            }
            return .system(size: size, weight: weight)
        }

        // Estilos listos para usar
        public static let title    = font(xl3, weight: .semibold)   // pantallas: "Documentos"
        public static let heading  = font(xl2, weight: .semibold)   // "Factura marzo 2025"
        public static let body     = font(base)
        public static let callout  = font(sm)
        public static let caption  = font(xs)
        public static let eyebrow  = font(xs, weight: .semibold)    // + tracking 0.12em, uppercase
        public static let eyebrowTracking: CGFloat = 0.12
    }

    // MARK: Spacing (base 4 pt)

    public enum Spacing {
        public static let x1: CGFloat  = 4
        public static let x2: CGFloat  = 8
        public static let x3: CGFloat  = 12
        public static let x4: CGFloat  = 16
        public static let x5: CGFloat  = 20
        public static let x6: CGFloat  = 24
        public static let x8: CGFloat  = 32
        public static let x10: CGFloat = 40
        public static let x12: CGFloat = 48
        public static let x16: CGFloat = 64
        public static let x20: CGFloat = 80
        public static let x24: CGFloat = 96

        /// Margen horizontal de pantalla en la app del escáner.
        public static let screenGutter: CGFloat = 20
    }

    // MARK: Radius (nunca esquinas duras en elementos interactivos)

    public enum Radius {
        public static let xs: CGFloat   = 4    // chips en línea
        public static let sm: CGFloat   = 6    // inputs, botones pequeños
        public static let md: CGFloat   = 10   // botones, badges  (--radius base)
        public static let lg: CGFloat   = 14   // tarjetas, menús, toasts
        public static let xl: CGFloat   = 20   // superficies grandes, modales
        public static let xl2: CGFloat  = 28   // hojas inferiores, hero cards
        public static let pill: CGFloat = 999  // tags, avatares, botones pill
    }

    // MARK: Elevation (dual-layer, fría, sin glows de color)

    public struct Shadow: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat

        public static let xs = Shadow(color: .black.opacity(0.30), radius: 1,  x: 0, y: 1)
        public static let sm = Shadow(color: .black.opacity(0.35), radius: 3,  x: 0, y: 1)
        public static let md = Shadow(color: .black.opacity(0.40), radius: 8,  x: 0, y: 4)
        public static let lg = Shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
        public static let xl = Shadow(color: .black.opacity(0.55), radius: 40, x: 0, y: 20)

        /// Resplandor emerald reservado para tarjetas con drill-in (uso puntual).
        public static let emeraldGlow = Shadow(color: Color(hex: "#10b981").opacity(0.35), radius: 20, x: 0, y: 10)
    }

    // MARK: Borders

    public enum Border {
        public static let hairline: CGFloat = 1
        public static let focusRingWidth: CGFloat = 3
        public static func focusRing(_ scheme: ColorScheme) -> Color {
            ColorToken.primary(scheme).opacity(0.40)
        }
    }

    // MARK: Motion

    public enum Motion {
        public static let fast: Double = 0.15
        public static let base: Double = 0.30
        public static let slow: Double = 0.70

        public static let easeOut  = Animation.timingCurve(0, 0, 0.2, 1, duration: base)
        public static let easeInOut = Animation.timingCurve(0.4, 0, 0.2, 1, duration: base)
        /// Muelle para affordances con carácter (toggles, reveal).
        public static let spring = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: base)

        /// Desplazamiento en y para fades (4–8 pt, nunca parallax).
        public static let fadeOffset: CGFloat = 6

        // Press state
        public static let pressScale: CGFloat = 0.98
        public static let pressIn: Double = 0.08
        public static let pressOut: Double = 0.12
    }

    // MARK: Overlays

    public enum Overlay {
        public static let scrim = Color.black.opacity(0.55)
        public static let blurRadius: CGFloat = 8   // 6–10 pt
    }
}

// MARK: - View sugar

public extension View {
    func dsShadow(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    /// Tarjeta estándar: superficie, hairline, radio lg, sombra sm.
    func dsCard(_ scheme: ColorScheme, radius: CGFloat = DS.Radius.lg) -> some View {
        self
            .padding(DS.Spacing.x4)
            .background(DS.ColorToken.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DS.ColorToken.border(scheme), lineWidth: DS.Border.hairline)
            )
            .dsShadow(.sm)
    }

    /// Etiqueta eyebrow: 12 pt semibold, mayúsculas, tracking 0.12em.
    func dsEyebrow() -> some View {
        self
            .font(DS.Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(DS.Typography.xs * DS.Typography.eyebrowTracking)
    }
}

// MARK: - Botón primario (emerald, texto negro, sin escala en hover)

public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.font(DS.Typography.base, weight: .semibold))
            .foregroundStyle(DS.Brand.ctaPrimaryFG)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(DS.ColorToken.primary(scheme))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? DS.Motion.pressScale : 1)
            .animation(.easeOut(duration: configuration.isPressed ? DS.Motion.pressIn : DS.Motion.pressOut),
                       value: configuration.isPressed)
    }
}
