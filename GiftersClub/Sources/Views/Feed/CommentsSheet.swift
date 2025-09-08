import SwiftUI

final class CommentsPresenter: ObservableObject {
    static let shared = CommentsPresenter()
    @Published var isPresented: Bool = false
    @Published var postId: String? = nil
    func present(postId: String) { self.postId = postId; self.isPresented = true }
    func dismiss() { self.isPresented = false }
}

struct CommentsSheet: View {
    let postId: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var comments: [SupabaseManager.DBCommentRow] = []
    @State private var newComment: String = ""
    private let supabase = SupabaseManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.3)).frame(width: 36, height: 5).padding(.top, 8)
            HStack {
                Text("Comments").font(.headline)
                Spacer()
            }.padding(.horizontal)

            List {
                ForEach(comments, id: \.id) { c in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color.secondary.opacity(0.3))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { if let u = c.profile?.username { NotificationCenter.default.post(name: .showGifterProfile, object: u) } }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.profile?.username ?? "user")
                                .font(.caption.weight(.semibold))
                                .contentShape(Rectangle())
                                .onTapGesture { if let u = c.profile?.username { NotificationCenter.default.post(name: .showGifterProfile, object: u) } }
                            Text(c.content)
                                .font(.subheadline)
                        }
                        Spacer()
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .listStyle(.plain)
            .refreshable { await load() }

            HStack(spacing: 10) {
                TextField("Add a comment...", text: $newComment, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { Task { await send() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .task { await load() }
        .presentationDetents([.medium, .large])
        .sheetStyleCompat()
    }

    private func load() async {
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            let res = try await supabase.fetchComments(postId: postId, limit: 50, offset: 0)
            await MainActor.run { comments = res }
        } catch {
            // Silent failure for now
        }
    }

    private func send() async {
        let trimmed = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await MainActor.run { isLoading = true }
        defer { Task { await MainActor.run { isLoading = false } } }
        do {
            if let created = try await supabase.addComment(postId: postId, content: trimmed) {
                await MainActor.run {
                    comments.insert(created, at: 0)
                    newComment = ""
                }
            }
        } catch {
            // keep text in field on failure
        }
    }
}
