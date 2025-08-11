import SwiftUI

struct ShimmerView: View {
    var cornerRadius: CGFloat = 12
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let width = proxy.size.width
                let phase = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.2)) / 1.2
                let offset = CGFloat(phase) * (width * 1.5) - width * 0.75
                let sweep = LinearGradient(
                    colors: [
                        Color.primary.opacity(0.06),
                        Color.primary.opacity(0.16),
                        Color.primary.opacity(0.06)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(sweep)
                            .mask(
                                Rectangle()
                                    .fill(.linearGradient(colors: [.black.opacity(0), .black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing))
                                    .offset(x: offset)
                            )
                    )
            }
        }
    }
}

#Preview("ShimmerView") {
    VStack(spacing: 16) {
        ShimmerView().frame(height: 56)
        ShimmerView().frame(height: 180)
    }
    .padding()
}
