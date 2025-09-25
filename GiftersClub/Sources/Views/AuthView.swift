import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var currentNonce: String?
    @State private var errorText: String? = nil
    @State private var isLoadingGoogle: Bool = false
    @State private var acceptedTerms: Bool = false

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
                    Text(agreementAttributed())
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
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
            .disabled(isLoadingGoogle || !acceptedTerms)
            .opacity((!isLoadingGoogle && acceptedTerms) ? 1.0 : 0.5)
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
            .disabled(!acceptedTerms)
            .opacity(acceptedTerms ? 1.0 : 0.5)
            .alert("Sign in error", isPresented: Binding(get: { errorText != nil }, set: { _ in errorText = nil })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            Spacer()
        }
    }
    private func signInGoogle() {
        guard acceptedTerms else { errorText = "Please agree to the Terms/EULA to continue."; return }
        // Persist local legal acceptance timestamp for server sync post sign-in
        UserDefaults.standard.set(Date(), forKey: "gc_eula_accepted_at")
        isLoadingGoogle = true
        Task { @MainActor in }
        Task {
            await SupabaseManager.shared.signInWithGoogle()
            await MainActor.run { isLoadingGoogle = false }
        }
    }

    // Compose an attributed sentence with inline links that wraps as one unit
    private func agreementAttributed() -> AttributedString {
        var s = AttributedString("I agree to the Terms of Service and Privacy Policy and understand there is zero tolerance for objectionable content or abusive users.")
        if let range1 = s.range(of: "Terms of Service") {
            s[range1].link = SupabaseConfig.webBase.appendingPathComponent("terms")
            s[range1].foregroundColor = .init(cgColor: UIColor.label.cgColor)
            s[range1].underlineStyle = .single
        }
        if let range2 = s.range(of: "Privacy Policy") {
            s[range2].link = SupabaseConfig.webBase.appendingPathComponent("privacy")
            s[range2].foregroundColor = .init(cgColor: UIColor.label.cgColor)
            s[range2].underlineStyle = .single
        }
        return s
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
