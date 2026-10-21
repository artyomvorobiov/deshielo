import SwiftUI
import UIKit

/// Цвета и константы оформления. Тёплая «бумажная» палитра, терракотовый акцент.
enum Theme {
    static let accent = Color(light: 0xB4532A, dark: 0xE07A4F)
    static let background = Color(light: 0xF6F2EC, dark: 0x121110)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1E1C1A)
    static let surfaceSecondary = Color(light: 0xEFE9E1, dark: 0x2A2724)
    static let parchment = Color(light: 0xEFE3CC, dark: 0x3A3226)
    static let ink = Color(light: 0x2B2420, dark: 0xF2EAE0)
    static let gold = Color(light: 0xA9844C, dark: 0xD4B27A)
    static let herb = Color(light: 0x5E7F37, dark: 0x8DAF55)
    static let separator = Color(light: 0xE4DCD1, dark: 0x34302B)

    static let cardRadius: CGFloat = 22
    static let smallRadius: CGFloat = 14
}

extension Color {
    /// Цвет из строки «#RRGGBB». При ошибке — нейтральный серый.
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Цвет, который меняется в тёмной теме.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }

    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        let value = UInt32(cleaned, radix: 16) ?? 0x888888
        self.init(rgb: cleaned.count == 6 ? value : 0x888888)
    }

    /// Относительная яркость 0…1 — чтобы выбирать контрастные цвета.
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

extension Font {
    /// Заголовки набраны антиквой (New York) — как в кулинарной книге.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }
}
