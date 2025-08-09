import SwiftUI

struct AccountView: View {
    var body: some View {
        List {
            Section("Account") {
                Text("Username")
                Text("Email")
                Text("Phone")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

