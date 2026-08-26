import SwiftUI

// Añadidos sobre `DesignTokens.swift`, que no se edita.
//
// Por qué existe esto: `DS.Typography.font(_:weight:)` acaba en
// `.system(size:)` cuando ni Geist ni Inter están en el bundle, y las fuentes
// del sistema creadas con un tamaño fijo **no** escalan con Dynamic Type. La
// Sprint 5 exige que la app funcione hasta los tamaños de accesibilidad, así
// que aquí se envuelven los mismos tamaños del sistema de diseño en un
// `relativeTo:` para que escalen. Los valores siguen viniendo de los tokens;
// esto solo cambia cómo se aplican.
extension DS.Typography {

    /// Fuente del sistema de diseño que sí responde a Dynamic Type.
    /// - Parameter textStyle: estilo de referencia sobre el que escalar.
    static func scaled(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        if UIFont(name: sans, size: size) != nil {
            return .custom(sans, size: size, relativeTo: textStyle)
        }
        if UIFont(name: sansFallback, size: size) != nil {
            return .custom(sansFallback, size: size, relativeTo: textStyle)
        }
        return .system(textStyle, weight: weight)
    }

    // Estilos de pantalla, ya escalables.
    static var screenTitle: Font { scaled(xl3, weight: .semibold, relativeTo: .largeTitle) }
    static var sectionTitle: Font { scaled(xl2, weight: .semibold, relativeTo: .title2) }
    static var rowTitle: Font { scaled(base, weight: .medium, relativeTo: .body) }
    static var bodyText: Font { scaled(base, relativeTo: .body) }
    static var calloutText: Font { scaled(sm, relativeTo: .callout) }
    static var captionText: Font { scaled(xs, relativeTo: .caption) }
}

// MARK: - Fondo de pantalla

private struct DSScreenBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(DS.ColorToken.background(scheme).ignoresSafeArea())
    }
}

extension View {
    /// Fondo de pantalla del sistema de diseño, respetando claro y oscuro.
    func dsScreenBackground() -> some View {
        modifier(DSScreenBackground())
    }
}
