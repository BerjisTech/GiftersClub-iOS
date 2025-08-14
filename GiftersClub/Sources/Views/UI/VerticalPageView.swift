import SwiftUI

struct VerticalPageView<Item: Identifiable & Hashable, Content: View>: View {
    let items: [Item]
    @Binding var selection: Int
    let content: (Int, Item) -> Content

    init(items: [Item], selection: Binding<Int>, @ViewBuilder content: @escaping (Int, Item) -> Content) {
        self.items = items
        self._selection = selection
        self.content = content
    }

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(items.indices, id: \.self) { i in
                    content(i, items[i])
                        .frame(width: geo.size.width, height: geo.size.height)
                        .rotationEffect(.degrees(-90))
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .rotationEffect(.degrees(90))
            // Fit rotated content
            .frame(width: geo.size.height, height: geo.size.width)
            // Center in parent
            .offset(x: (geo.size.width - geo.size.height) / 2, y: (geo.size.height - geo.size.width) / 2)
        }
    }
}

