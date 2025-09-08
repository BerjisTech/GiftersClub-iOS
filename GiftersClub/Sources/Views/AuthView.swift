import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var currentNonce: String?

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
#if targetEnvironment(simulator)
            Button(action: simSignInWithGoogle) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Continue with Google (sim)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
#endif
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
                    Task { await SupabaseManager.shared.signInWithApple(idToken: idToken, nonce: nonce) }
                case .failure:
                    break
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 45)
            .padding(.horizontal, 24)
            Spacer()
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

#if targetEnvironment(simulator)
private func simSignInWithGoogle() {
    Task {
        do {
            _ = try await SupabaseManager.shared.client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.redirectURL
            )
        } catch {
            // ignore in simulator
        }
    }
}
#endif
