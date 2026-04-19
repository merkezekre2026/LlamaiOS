import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsRecords: [AppSettingsRecord]
    @State private var selectedTab: AppTab = .chat

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatRootView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.chat)

            ModelsView()
                .tabItem { Label("Models", systemImage: "shippingbox") }
                .tag(AppTab.models)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(Design.accent)
        .onAppear(perform: ensureSettings)
        .sheet(isPresented: firstLaunchBinding) {
            FirstLaunchView()
                .presentationDetents([.large])
        }
    }

    private var firstLaunchBinding: Binding<Bool> {
        Binding {
            settingsRecords.first?.hasSeenFirstLaunch == false
        } set: { newValue in
            if newValue == false {
                settingsRecords.first?.hasSeenFirstLaunch = true
                try? modelContext.save()
            }
        }
    }

    private func ensureSettings() {
        guard settingsRecords.isEmpty else { return }
        modelContext.insert(AppSettingsRecord())
        try? modelContext.save()
    }
}

private enum AppTab: Hashable {
    case chat
    case models
    case settings
}
