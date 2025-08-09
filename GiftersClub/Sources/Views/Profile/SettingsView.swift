import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            Section("Settings") {
                NavigationLink("Security") { Text("Security Settings (TODO)") }
                NavigationLink("Moderation") { Text("Moderation Settings (TODO)") }
                NavigationLink("Interaction") { Text("Interaction Settings (TODO)") }
                NavigationLink("General") { Text("General Settings (TODO)") }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

