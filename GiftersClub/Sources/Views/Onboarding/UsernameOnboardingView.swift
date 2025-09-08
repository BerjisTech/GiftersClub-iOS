import SwiftUI

struct UsernameOnboardingView: View {
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var username: String = ""
    @State private var errorText: String? = nil
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Pick a username").font(.title2.weight(.bold))
                    Text("We use this instead of your email for your profile and mentions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                VStack(alignment: .leading, spacing: 10) {
                    TextField("@username", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
                    if let err = errorText { Text(err).font(.footnote).foregroundStyle(.red) }
                    Text("3–20 characters: letters, numbers, or underscore")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                Button(action: save) {
                    if isSaving { ProgressView().progressViewStyle(.circular) }
                    else { Text("Continue").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSaving)
                .padding(.horizontal)
                Spacer()
            }
            .navigationTitle("")
        }
    }

    private var isValid: Bool {
        username.range(of: "^[A-Za-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    private func save() {
        errorText = nil
        isSaving = true
        Task {
            do {
                try await supabase.setUsername(username)
            } catch {
                await MainActor.run { errorText = (error as NSError).localizedDescription }
            }
            await MainActor.run { isSaving = false }
        }
    }
}

