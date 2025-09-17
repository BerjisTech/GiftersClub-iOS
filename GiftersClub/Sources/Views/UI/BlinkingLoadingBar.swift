import SwiftUI

struct BlinkingLoadingBar: View {
    @State private var isWhite = false
    var height: CGFloat = 3
    var body: some View {
        Rectangle()
            .fill(isWhite ? Color.white : Color.black)
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    isWhite.toggle()
                }
            }
    }
}

