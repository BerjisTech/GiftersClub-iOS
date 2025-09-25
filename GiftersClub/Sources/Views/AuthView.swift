import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var currentNonce: String?
    @State private var errorText: String? = nil
    @State private var isLoadingGoogle: Bool = false
    @State private var acceptedTerms: Bool = false
    @State private var isOver18: Bool = false

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
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $acceptedTerms) {
                    HStack(spacing: 4) {
                        Text("I agree to the ")
                        Link("Terms/EULA", destination: SupabaseConfig.webBase.appendingPathComponent("terms"))
                        Text(" and understand we have zero tolerance for objectionable content or abuse.")
                    }
                }
                .toggleStyle(.switch)
                Toggle(isOn: $isOver18) {
                    Text("I confirm I am 18+")
                }
                .toggleStyle(.switch)
                if let err = errorText { Text(err).foregroundColor(.red).font(.footnote) }
            }
            .padding(.horizontal, 24)
            Button(action: signInGoogle) {
                HStack(spacing: 8) {
                    if isLoadingGoogle { ProgressView().progressViewStyle(.circular) }
                    else { Image(systemName: "globe") }
                    Text(isLoadingGoogle ? "Signing in…" : "Continue with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingGoogle || !acceptedTerms || !isOver18)
            .padding(.horizontal, 24)
            // Sign in with Apple (native)
            SignInWithAppleButton(.signIn) { request in
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                // Send SHA256(nonce) as per Apple’s recommended flow
                request.nonce = sha256(nonce)
            } onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8),
                          let nonce = currentNonce else { return }
                    Task {
                        do {
                            try await SupabaseManager.shared.signInWithApple(idToken: idToken, nonce: nonce)
                        } catch {
                            await MainActor.run { errorText = "Sign in failed. Please try again later." }
                        }
                    }
                case .failure:
                    errorText = "Sign in was cancelled or failed."
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 45)
            .padding(.horizontal, 24)
            .disabled(!acceptedTerms || !isOver18)
            .alert("Sign in error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            Spacer()
        }
    }
    private func signInGoogle() {
        guard acceptedTerms && isOver18 else { errorText = "Please confirm 18+ and agree to the Terms/EULA."; return }
        // Persist local legal acceptance for server sync post sign-in
        UserDefaults.standard.set(true, forKey: "gc_is_over_18")
        UserDefaults.standard.set(Date(), forKey: "gc_eula_accepted_at")
        isLoadingGoogle = true
        Task { @MainActor in }
        Task {
            await SupabaseManager.shared.signInWithGoogle()
            await MainActor.run { isLoadingGoogle = false }
        }
    }
}

struct AuthView_Previews: PreviewProvider {
    static var previews: some View { AuthView() }
}

// MARK: - Nonce Helpers
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        var randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
        randoms.withUnsafeMutableBytes { bytes in
            for idx in 0..<bytes.count {
                if remainingLength == 0 { break }
                let rand = Int(bytes[idx])
                if rand < charset.count {
                    result.append(charset[rand])
                    remainingLength -= 1
                }
            }
        }
    }
    return result
}

import CryptoKit
private func sha256(_ input: String) -> String {
    let data = Data(input.utf8)
    let hashed = SHA256.hash(data: data)
    return hashed.compactMap { String(format: "%02x", $0) }.joined()
}
