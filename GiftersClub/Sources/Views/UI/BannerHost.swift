import SwiftUI

enum BannerStyle {
    case success, info, warning, error

    var colors: [Color] {
        switch self {
        case .success: return [AppColors.successStart, AppColors.successEnd]
        case .info:    return [AppColors.primaryStart, AppColors.primaryEnd]
        case .warning: return [AppColors.warningStart, AppColors.warningEnd]
        case .error:   return [AppColors.dangerStart, AppColors.dangerEnd]
        }
    }
    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
}

struct Banner: Identifiable {
    let id = UUID()
    var title: String
    var style: BannerStyle
    var action: (() -> Void)?
    var duration: TimeInterval = 3
}

final class BannerQueue: ObservableObject {
    @Published var banners: [Banner] = []
    init() {}
    func show(_ banner: Banner) {
        banners.append(banner)
        UIAccessibility.post(notification: .announcement, argument: banner.title)
    }
    func dismiss(_ banner: Banner) {
        banners.removeAll { $0.id == banner.id }
    }
}

struct BannerHost: View {
    @EnvironmentObject var queue: BannerQueue

    init() {}

    var body: some View {
        VStack(spacing: 6) {
            ForEach(queue.banners) { banner in
                BannerView(banner: banner)
                    .onTapGesture {
                        banner.action?()
                        queue.dismiss(banner)
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .allowsHitTesting(!queue.banners.isEmpty)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(
            .spring(response: 0.35, dampingFraction: 0.9),
            value: queue.banners.map { $0.id }
        )
    }
}

private struct BannerView: View {
    let banner: Banner
    @State private var isVisible = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.style.symbol)
                .imageScale(.medium)
                .foregroundStyle(Color.white)
            Text(banner.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(colors: banner.style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + banner.duration) {
                withAnimation {
                    isVisible = false
                }
            }
        }
        .opacity(isVisible ? 1 : 0)
    }
}

#Preview("BannerHost") {
    ZStack(alignment: .top) {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        BannerHost()
    }
    .environmentObject({
        let q = BannerQueue()
        q.show(Banner(title: "Your post has been created", style: .success))
        return q
    }())
}
