import SwiftUI

enum RootTab { case home, explore, chat, profile }

struct CustomBottomBar: View {
    static let barHeight: CGFloat = 70
    @Binding var selected: RootTab
    var onCompose: () -> Void

    var body: some View {
        ZStack {
            // Background bar
            Rectangle().fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
            HStack(alignment: .center) {
                barItem(icon: "house.fill", tab: .home)
                Spacer()
                barItem(icon: "safari.fill", tab: .explore)
                Spacer(minLength: 0)
                composeButton
                Spacer(minLength: 0)
                barItem(icon: "bubble.left.and.bubble.right.fill", tab: .chat)
                Spacer()
                barItem(icon: "person.crop.circle.fill", tab: .profile)
            }
            .padding(.horizontal, 24)
        }
        .frame(height: Self.barHeight)
    }

    private func barItem(icon: String, tab: RootTab) -> some View {
        Button(action: { selected = tab }) {
            Image(systemName: icon)
                .font(.system(size: selected == tab ? 20 : 18, weight: .semibold))
                .foregroundStyle(selected == tab ? AppColors.primaryEnd : Color.secondary)
                .frame(width: 44, height: 44)
        }
    }

    private var composeButton: some View {
        Button(action: onCompose) {
            ZStack {
                Circle().fill(LinearGradient(colors: [AppColors.primaryStart, AppColors.primaryEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "plus")
                    .foregroundStyle(.white)
                    .font(.title2.weight(.bold))
            }
            .frame(width: 58, height: 58)
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
        }
        .offset(y: -10)
    }
}
