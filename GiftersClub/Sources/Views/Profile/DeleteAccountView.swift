import SwiftUI

struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @State private var acknowledged = false
    @State private var isSubmitting = false
    @State private var errorText: String? = nil
    @State private var success = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Account")
                .font(.title2.weight(.semibold))
            Text("Request permanent deletion of your account and associated data. This process may take up to 7 days. You can continue to use the app until your request is processed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle(isOn: $acknowledged) {
                Text("I understand this action is irreversible.")
            }

            if let err = errorText {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if success {
                Text("Your account deletion request has been received.")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView() }
                    Text("Request Account Deletion")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!acknowledged || isSubmitting)

            Spacer()
        }
        .padding()
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        guard supabase.user != nil else { return }
        await MainActor.run { isSubmitting = true; errorText = nil; success = false }
        do {
            try await supabase.requestAccountDeletion()
            await MainActor.run { success = true }
        } catch {
            await MainActor.run { errorText = (error as NSError).localizedDescription }
        }
        await MainActor.run { isSubmitting = false }
    }
}

