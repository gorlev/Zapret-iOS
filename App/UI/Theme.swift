import SwiftUI
import UIKit

/// The accent color, the same as ZapretMac's: Petrol, the top of the icon's
/// petrol-to-navy gradient. Everything else is Apple's look.
enum Palette {
    static let petrol = Shades(light: 0x5CC8DA, base: 0x0B7285, deep: 0x095868)
    static let navy: UInt32 = 0x0D1A47

    struct Shades { let light: UInt32; let base: UInt32; let deep: UInt32 }

    static var accent: Color { Color(hex: petrol.base) }
    /// Accent-colored text and symbols: the deep shade in light mode, the light shade in dark mode.
    static var accentText: Color { Color(light: petrol.deep, dark: petrol.light) }
    static var onAccent: Color { .white }
    /// The power button's fill while on, like the app icon.
    static var heroFill: LinearGradient {
        LinearGradient(colors: [Color(hex: petrol.base), Color(hex: navy)], startPoint: .top, endPoint: .bottom)
    }
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
