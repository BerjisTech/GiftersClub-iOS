import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self = Color(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}

enum Backgrounds {
    // Matches Angular .bg-gift-card-gradient
    static let giftCard = LinearGradient(
        colors: [
            Color(hex: "#FF6B9D"),
            Color(hex: "#9747FF"),
            Color(hex: "#47B9FF")
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let amber = LinearGradient(
        colors: [Color(hex: "#FFC107"), Color(hex: "#FF9800"), Color(hex: "#FF5722")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let rose = LinearGradient(
        colors: [Color(hex: "#FF7E5F"), Color(hex: "#FF6B9D"), Color(hex: "#FF3D00")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let slate = LinearGradient(
        colors: [Color("slate_500"), Color("slate_600"), Color("slate_700")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let emerald = LinearGradient(
        colors: [Color(hex: "#4CAF50"), Color(hex: "#8BC34A"), Color(hex: "#CDDC39")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let yellow = LinearGradient(
        colors: [Color(hex: "#FFF700"), Color(hex: "#FFE066"), Color(hex: "#FFD600")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let blue = LinearGradient(
        colors: [Color(hex: "#6EC1E4"), Color(hex: "#3A8DFF"), Color(hex: "#0057B8")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let green = LinearGradient(
        colors: [Color(hex: "#A8FF78"), Color(hex: "#78FFD6"), Color(hex: "#28C76F")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let red = LinearGradient(
        colors: [Color(hex: "#FF5858"), Color(hex: "#FF7E5F"), Color(hex: "#FF0000")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let purple = LinearGradient(
        colors: [Color(hex: "#B721FF"), Color(hex: "#21D4FD"), Color("violet_700")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let orange = LinearGradient(
        colors: [Color(hex: "#FFB347"), Color(hex: "#FF7E5F"), Color(hex: "#FF6A00")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let pink = LinearGradient(
        colors: [Color(hex: "#FF6B9D"), Color(hex: "#FFB6C1"), Color(hex: "#FF69B4")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let teal = LinearGradient(
        colors: [Color(hex: "#1DE9B6"), Color(hex: "#1DC8E9"), Color(hex: "#008080")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let cyan = LinearGradient(
        colors: [Color(hex: "#00FFF0"), Color(hex: "#00CFFF"), Color(hex: "#00B7EB")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let indigo = LinearGradient(
        colors: [Color("indigo_400"), Color("indigo_600"), Color("indigo_800")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let violet = LinearGradient(
        colors: [Color("violet_400"), Color("violet_600"), Color("violet_800")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let brown = LinearGradient(
        colors: [Color(hex: "#A0522D"), Color(hex: "#CD853F"), Color(hex: "#8B4513")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let gray = LinearGradient(
        colors: [Color("gray_300"), Color("gray_500"), Color("gray_700")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let black = LinearGradient(
        colors: [Color(hex: "#434343"), Color.black],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let white = LinearGradient(
        colors: [Color.white, Color(hex: "#F8F8F8")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

