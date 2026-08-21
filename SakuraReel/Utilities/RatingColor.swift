import SwiftUI

struct RatingColor {
    static func color(for rating: Int) -> Color {
        switch rating {
        case 0:      return Color(hex: "E5E5EA")
        case 1...3:  return Color(hex: "C7C7CC")
        case 4...5:  return Color(hex: "F8A5B6")
        case 6...7:  return Color(hex: "F08080")
        case 8...9:  return Color(hex: "E88398")
        case 10:     return Color(hex: "E2556B")
        default:     return Color.gray
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
