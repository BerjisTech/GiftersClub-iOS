import SwiftUI

enum AppColors {
    static let primaryStart = Color(hex: 0x00C6FF)
    static let primaryEnd   = Color(hex: 0x0072FF)
    static let dangerStart  = Color(hex: 0xFF7E5F)
    static let dangerEnd    = Color(hex: 0xFF3D00)
    static let successStart = Color(hex: 0x00E676)
    static let successEnd   = Color(hex: 0x00BFA5)
    static let warningStart = Color(hex: 0xFFC107)
    static let warningEnd   = Color(hex: 0xFF9800)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

