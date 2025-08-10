import SwiftUI

#if canImport(Lottie)
import Lottie

struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .playOnce
    var contentMode: UIView.ContentMode = .scaleAspectFit
    var onCompleted: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        let animationView = LottieAnimationView(name: name)
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.loopMode = loopMode
        animationView.contentMode = contentMode
        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.animationView = animationView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.playIfNeeded(onCompleted: onCompleted)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var animationView: LottieAnimationView?
        private var hasPlayed = false
        func playIfNeeded(onCompleted: (() -> Void)?) {
            guard let view = animationView, !hasPlayed else { return }
            hasPlayed = true
            view.play { _ in onCompleted?() }
        }
    }
}
#else
// Fallback stub so project builds without Lottie until added via SPM
struct LottieView: View {
    let name: String
    var loopMode: Int = 0
    var contentMode: Int = 0
    var onCompleted: (() -> Void)? = nil
    var body: some View { Color.clear.onAppear { onCompleted?() } }
}
#endif

