import SwiftUI

struct ComposeChoiceSheet: View {
    var onCreatePost: () -> Void
    var onGoLive: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 44, height: 5).padding(.top, 8)
            Text("What would you like to do?")
                .font(.headline)
                .padding(.top, 4)

            VStack(spacing: 12) {
                GradientButton(title: "Go Live") { onGoLive() }
                GradientButton(title: "Create Post", state: .normal) { onCreatePost() }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.15))
                    )
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Text("You can stream live or create a photo/video/text post.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .presentationDetents([.height(220), .medium])
        .sheetStyleCompat()
    }
}

#Preview {
    ComposeChoiceSheet(onCreatePost: {}, onGoLive: {})
}
