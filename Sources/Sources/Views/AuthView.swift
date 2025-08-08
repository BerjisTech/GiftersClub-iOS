import SwiftUI

struct AuthView: View {
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 12) {
                Text("GiftersClub")
                    .font(.largeTitle).bold()
                Text("Sign in to continue")
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: signIn) {
                HStack {
                    Image(systemName: "globe")
                    Text("Continue with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func signIn() {
        isLoading = true
        Task {
            await SupabaseManager.shared.signInWithGoogle()
            isLoading = false
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View { AuthView() }
}

