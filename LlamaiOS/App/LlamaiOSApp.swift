import SwiftData
import SwiftUI

@main
struct LlamaiOSApp: App {
    @StateObject private var engine = LlamaEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
        .modelContainer(Self.modelContainer)
    }

    private static var modelContainer: ModelContainer {
        do {
            let schema = Schema([
                ConversationRecord.self,
                MessageRecord.self,
                ModelRecord.self,
                GenerationPresetRecord.self,
                AppSettingsRecord.self
            ])
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
    }
}
