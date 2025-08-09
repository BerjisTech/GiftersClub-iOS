import SwiftUI

struct ShimmerView: View {
    var cornerRadius: CGFloat = 12
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let gradient = LinearGradient(
                colors: [
                    Color.primary.opacity(0.06),
                    Color.primary.opacity(0.12),
                    Color.primary.opacity(0.06)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(gradient)
                        .mask(
                            Rectangle()
                                .fill(.linearGradient(colors: [.black.opacity(0), .black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing))
                                .offset(x: animOffset(width: width))
                        )
                )
                .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: UUID())
        }
    }

    private func animOffset(width: CGFloat) -> CGFloat {
        // Use time-based offset to avoid state; simple shimmer sweep
        let t = CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 1.2)
        return (CGFloat(t) / 1.2) * (width * 1.5) - width * 0.75
    }
}

#Preview("ShimmerView") {
    VStack(spacing: 16) {
        ShimmerView().frame(height: 56)
        ShimmerView().frame(height: 180)
    }
    .padding()
}
