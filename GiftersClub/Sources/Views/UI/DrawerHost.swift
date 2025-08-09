import SwiftUI

struct DrawerModel {
    var title: String
    var message: String
    var primaryTitle: String
    var primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var detents: Set<PresentationDetent> = [.height(140), .medium]
}

final class DrawerManager: ObservableObject {
    @Published var isPresented: Bool = false
    @Published var model: DrawerModel = DrawerModel(title: "", message: "", primaryTitle: "OK", primaryAction: {})

    init() {}

    func present(_ model: DrawerModel) {
        self.model = model
        withAnimation { self.isPresented = true }
    }
    func dismiss() {
        withAnimation { self.isPresented = false }
    }
}

struct DrawerHost<Content: View>: View {
    @EnvironmentObject var drawer: DrawerManager
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        content()
            .sheet(isPresented: $drawer.isPresented) {
                DrawerSheet(model: drawer.model) { drawer.dismiss() }
                    .presentationDetents(drawer.model.detents)
                    .presentationCornerRadius(20)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}

private struct DrawerSheet: View {
    var model: DrawerModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 5).padding(.top, 8)
            Text(model.title).font(.headline)
            Text(model.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 12) {
                if let secondary = model.secondaryTitle, let action = model.secondaryAction {
                    Button(secondary) { action() }.buttonStyle(.bordered)
                }
                Button(model.primaryTitle) { model.primaryAction() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}

#Preview("DrawerHost") {
    DrawerHost {
        VStack { Text("Demo"); Spacer(); }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
    }
    .environmentObject({
        let mgr = DrawerManager()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            mgr.present(DrawerModel(
                title: "Action Required",
                message: "Do you want to subscribe to @creator?",
                primaryTitle: "Subscribe",
                primaryAction: {},
                secondaryTitle: "Cancel",
                secondaryAction: {}
            ))
        }
        return mgr
    }())
}
