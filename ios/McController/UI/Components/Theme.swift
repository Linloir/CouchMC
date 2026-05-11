import SwiftUI

/// Centralised material / surface picker. Two design languages:
///   - `.standard`     — iOS 18 system materials at moderate prominence.
///   - `.liquidGlass`  — brighter, glossier surfaces approximating the
///                       iOS 26 Liquid Glass look using iOS 18 primitives.
///
/// **Upgrade path for iOS 26 Liquid Glass APIs**: when building with the
/// iOS 26 SDK, replace the `.liquidGlass` branch implementations with the
/// real `.glassEffect(...)` modifier. The branch points are clearly marked
/// below with `// LIQUID_GLASS_UPGRADE`.
struct Theme {

    enum Surface { case card, panel, prominent }

    let language: DesignLanguage

    @ViewBuilder
    func surface<V: View>(_ surface: Surface = .card, @ViewBuilder _ content: () -> V) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        switch language {
        case .standard:
            content()
                .background(material(for: surface), in: shape)
        case .liquidGlass:
            // LIQUID_GLASS_UPGRADE — replace with `.glassEffect(...)` on iOS 26+.
            content()
                .background(material(for: surface), in: shape)
                .overlay(
                    shape
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.clear,
                                ],
                                startPoint: .top, endPoint: .center
                            )
                        )
                        .blendMode(.overlay)
                        .allowsHitTesting(false)
                )
        }
    }

    private func material(for surface: Surface) -> Material {
        switch surface {
        case .card:      return .regularMaterial
        case .panel:     return .thickMaterial
        case .prominent: return .ultraThinMaterial
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = Theme(language: .standard)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
