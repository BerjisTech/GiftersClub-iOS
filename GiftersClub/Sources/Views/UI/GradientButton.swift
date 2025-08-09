import SwiftUI

enum GradientButtonState: Equatable {
    case normal
    case loading
    case success
    case error
}

struct GradientButtonStyleConfig {
    var cornerRadius: CGFloat = 10
    var height: CGFloat = 48
    var horizontalPadding: CGFloat = 16
}

struct GradientButton: View {
    var title: String
    var state: GradientButtonState
    var config: GradientButtonStyleConfig = .init()
    var action: () -> Void

    @Environment(\.colorScheme) private var _scheme
    private var scheme: ColorScheme { _scheme }
    @State private var animatedColors: [Color] = [AppColors.primaryStart, AppColors.primaryEnd]

    init(title: String,
         state: GradientButtonState = .normal,
         config: GradientButtonStyleConfig = .init(),
         action: @escaping () -> Void) {
        self.title = title
        self.state = state
        self.config = config
        self.action = action
    }

    private func colors(for state: GradientButtonState) -> [Color] {
        switch state {
        case .normal:  return [AppColors.primaryStart, AppColors.primaryEnd]
        case .loading: return [AppColors.primaryStart.opacity(0.7), AppColors.primaryEnd.opacity(0.7)]
        case .success: return [AppColors.successStart, AppColors.successEnd]
        case .error:   return [AppColors.dangerStart, AppColors.dangerEnd]
        }
    }

    var body: some View {
        Button(action: {
            guard state != .loading else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            ZStack {
                LinearGradient(colors: animatedColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .opacity(state == .loading ? 0.0 : 1.0)
                if state == .loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: config.height)
            .clipShape(RoundedRectangle(cornerRadius: config.cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.25 : 0.15), radius: 8, y: 4)
            .padding(.horizontal, config.horizontalPadding)
            // Animation handled via withAnimation on state change
        }
        .buttonStyle(.plain)
        .onChange(of: state) { _, newValue in
            withAnimation(.easeInOut(duration: 0.35)) {
                animatedColors = colors(for: newValue)
            }
            if newValue == .success {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else if newValue == .error {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        .onAppear {
            animatedColors = colors(for: state)
        }
    }
}

#Preview("GradientButton") {
    VStack(spacing: 16) {
        GradientButton(title: "Create Post", state: .normal) {}
        GradientButton(title: "Creating…", state: .loading) {}
        GradientButton(title: "Created", state: .success) {}
        GradientButton(title: "Retry", state: .error) {}
    }
    .padding()
    .background(Color(uiColor: .systemBackground))
}
