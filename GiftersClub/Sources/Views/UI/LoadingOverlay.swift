import SwiftUI

/// A full-screen overlay with a pulsing logo, suitable for masking
/// partially-rendered pages while data loads.
struct LoadingOverlay: View {
    var isPresented: Bool
    var background: Color = Color(.systemBackground)

    @State private var scale: CGFloat = 0.9
    @State private var isAnimating = false

    var body: some View {
        Group {
            if isPresented {
                ZStack {
                    background.ignoresSafeArea()
                    // Use the app logo from asset catalog if available
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .scaleEffect(scale)
                        .opacity(0.95)
                        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                        .onAppear {
                            guard !isAnimating else { return }
                            isAnimating = true
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                scale = 1.08
                            }
                        }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    /// Convenience to present a full-screen pulsing-logo overlay while loading.
    func loadingOverlay(_ isPresented: Bool, background: Color = Color(.systemBackground)) -> some View {
        ZStack {
            self
            LoadingOverlay(isPresented: isPresented, background: background)
        }
    }
}

