import SwiftUI

struct CreatePostButton: View {
    @State private var showComposer = false
    var body: some View {
        ZStack {
            Button(action: { showComposer = true }) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [AppColors.primaryStart, AppColors.primaryEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "plus")
                        .foregroundStyle(.white)
                        .font(.title2.weight(.bold))
                }
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(
            // hit target only on the button
            Color.clear
        )
        .sheet(isPresented: $showComposer) { CreatePostSheet() }
    }
}

struct CreatePostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Post").font(.title3.weight(.semibold))
                TextEditor(text: $text)
                    .frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1)))
                Spacer()
                GradientButton(title: "Post") { dismiss() }
            }
            .padding()
            .navigationTitle("")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
