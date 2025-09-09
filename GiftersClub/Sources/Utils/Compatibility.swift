import SwiftUI

extension View {
    @ViewBuilder
    func sheetStyleCompat() -> some View {
        if #available(iOS 16.4, *) {
            self
                .presentationCornerRadius(20)
                .presentationBackground(.ultraThinMaterial)
        } else {
            self
        }
    }

    @ViewBuilder
    func titleDisplayInlineCompat() -> some View {
        if #available(iOS 17.0, *) {
            self.toolbarTitleDisplayMode(.inline)
        } else {
            self.navigationBarTitleDisplayMode(.inline)
        }
    }

    // iOS 17+: use native navigationDestination(item:)
    @available(iOS 17.0, *)
    @ViewBuilder
    func navigationDestinationCompat<Item: Identifiable & Hashable, Destination: View>(item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> Destination) -> some View {
        self.navigationDestination(item: item, destination: destination)
    }

    // iOS 16 and below: fall back to sheet(item:)
    @ViewBuilder
    func navigationDestinationCompat<Item: Identifiable, Destination: View>(item: Binding<Item?>, @ViewBuilder destination: @escaping (Item) -> Destination) -> some View {
        self.sheet(item: item, content: destination)
    }
}
