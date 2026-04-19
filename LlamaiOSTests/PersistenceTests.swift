import SwiftData
import XCTest
@testable import LlamaiOS

@MainActor
final class PersistenceTests: XCTestCase {
    func testConversationMessageAndSettingsRoundTrip() throws {
        let schema = Schema([
            ConversationRecord.self,
            MessageRecord.self,
            ModelRecord.self,
            GenerationPresetRecord.self,
            AppSettingsRecord.self
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = container.mainContext

        let settings = AppSettingsRecord()
        let model = ModelRecord(displayName: "Tiny", originalFileName: "tiny.gguf", localPath: "/tmp/tiny.gguf", fileSize: 4, isSelected: true)
        let conversation = ConversationRecord(title: "Test", selectedModelID: model.id)
        let message = MessageRecord(role: .user, content: "Hello", conversation: conversation)
        conversation.messages.append(message)
        settings.selectedModelID = model.id

        context.insert(settings)
        context.insert(model)
        context.insert(conversation)
        try context.save()

        let fetchedConversations = try context.fetch(FetchDescriptor<ConversationRecord>())
        let fetchedSettings = try context.fetch(FetchDescriptor<AppSettingsRecord>())

        XCTAssertEqual(fetchedConversations.count, 1)
        XCTAssertEqual(fetchedConversations.first?.messages.first?.content, "Hello")
        XCTAssertEqual(fetchedSettings.first?.selectedModelID, model.id)
    }
}
