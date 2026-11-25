import Observation
import SwiftUI
import UIKit

/// One accent color in three shades, the same list as ZapretMac's Theme. Everything
/// else is Apple's look. People pick it in Settings > Appearance. Light and dark
/// mode follow the system.
struct Theme: Identifiable, Hashable {
    struct Shades: Hashable { let light: UInt32; let base: UInt32; let deep: UInt32 }

    let id: String
    let name: String
    let shades: Shades
    /// Text on the accent: white, or dark ink for bright accents like yellow.
    var darkText = false
    /// Where the power button's gradient ends. nil: a plain accent gradient.
    var gradientEnd: UInt32?

    var accent: Color { Color(hex: shades.base) }
    /// Accent-colored text and symbols: the deep shade in light mode, the light shade in dark mode.
    var accentText: Color { Color(light: shades.deep, dark: shades.light) }
    var onAccent: Color { darkText ? Color(hex: 0x16161C) : .white }
    /// The power button's fill while on.
    var heroFill: LinearGradient {
        let colors = if let gradientEnd {
            [Color(hex: shades.base), Color(hex: gradientEnd)]
        } else {
            [accent.opacity(0.85), accent]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    /// The default. On the Mac "System" follows the Mac's accent; on iOS it is the
    /// app's own Petrol, the top of the icon's petrol-to-navy gradient.
    static let petrol = Theme(id: "petrol", name: "Petrol", shades: .init(light: 0x5CC8DA, base: 0x0B7285, deep: 0x095868),
                              gradientEnd: 0x0D1A47)

    static let all: [Theme] = [
        petrol,
        Theme(id: "blue", name: "Blue", shades: .init(light: 0x7CC0FF, base: 0x0A84FF, deep: 0x0064D2)),
        Theme(id: "indigo", name: "Indigo", shades: .init(light: 0xA5ADFF, base: 0x5E6AD2, deep: 0x4650B8)),
        Theme(id: "violet", name: "Violet", shades: .init(light: 0xB9A6FF, base: 0x7B5CFF, deep: 0x6342E6)),
        Theme(id: "pink", name: "Pink", shades: .init(light: 0xFF9CCB, base: 0xE84A93, deep: 0xC0306F)),
        Theme(id: "red", name: "Red", shades: .init(light: 0xFF8A9A, base: 0xE11D48, deep: 0xBE123C)),
        Theme(id: "orange", name: "Orange", shades: .init(light: 0xFFB87A, base: 0xF97316, deep: 0xC2410C)),
        Theme(id: "yellow", name: "Yellow", shades: .init(light: 0xFFE17A, base: 0xF5B800, deep: 0x946800), darkText: true),
        Theme(id: "mint", name: "Mint", shades: .init(light: 0x8EEBC4, base: 0x2BC48A, deep: 0x0F7A55), darkText: true),
        Theme(id: "teal", name: "Teal", shades: .init(light: 0x8BE9F5, base: 0x06B6D4, deep: 0x0E7490), darkText: true),
        Theme(id: "graphite", name: "Graphite", shades: .init(light: 0xC7C7CC, base: 0x7C7C84, deep: 0x55555C)),
    ]
}

/// The chosen accent, saved in the App Group's defaults. Views that read `theme`
/// redraw when it changes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var themeID: String {
        didSet { AppGroup.defaults.set(themeID, forKey: "appearance.accent") }
    }

    var theme: Theme { Theme.all.first { $0.id == themeID } ?? Theme.petrol }

    private init() {
        themeID = AppGroup.defaults.string(forKey: "appearance.accent") ?? Theme.petrol.id
    }
}

/// Accent tokens for views. Never hard-code an accent hex in a view.
enum Palette {
    static var accent: Color { ThemeStore.shared.theme.accent }
    /// Accent-colored text and symbols: the deep shade in light mode, the light shade in dark mode.
    static var accentText: Color { ThemeStore.shared.theme.accentText }
    static var onAccent: Color { ThemeStore.shared.theme.onAccent }
    /// The power button's fill while on, like the app icon.
    static var heroFill: LinearGradient { ThemeStore.shared.theme.heroFill }
}

/// The spacing scale, on a 4 pt grid, as in ZapretMac.
enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
    static let margin: CGFloat = 20
}

extension View {
    /// A rounded, lightly outlined card, like ZapretMac's.
    func card() -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground),
                   in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
