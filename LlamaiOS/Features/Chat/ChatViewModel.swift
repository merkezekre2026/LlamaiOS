import Foundation
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var draft = ""
    @Published var editingMessageID: UUID?
    @Published var editingText = ""
    @Published var errorMessage: String?
    @Published var isSending = false

    private let promptBuilder = PromptBuilder()
    private var streamTask: Task<Void, Never>?

    func send(
        in conversation: ConversationRecord,
        model: ModelRecord?,
        engine: LlamaEngine,
        context: ModelContext
    ) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        appendAndGenerate(userText: text, in: conversation, model: model, engine: engine, context: context)
    }

    func stop(engine: LlamaEngine) {
        streamTask?.cancel()
        streamTask = nil
        engine.stopGeneration()
        isSending = false
    }

    func regenerate(
        in conversation: ConversationRecord,
        model: ModelRecord?,
        engine: LlamaEngine,
        context: ModelContext
    ) {
        let sorted = sortedMessages(conversation)
        guard let lastAssistant = sorted.last(where: { $0.role == .assistant }) else { return }
        context.delete(lastAssistant)
        conversation.updatedAt = .now
        try? context.save()
        generateAssistantResponse(in: conversation, model: model, engine: engine, context: context)
    }

    func beginEditingLastUserMessage(in conversation: ConversationRecord) {
        guard let lastUser = sortedMessages(conversation).last(where: { $0.role == .user }) else { return }
        editingMessageID = lastUser.id
        editingText = lastUser.content
    }

    func commitEdit(
        in conversation: ConversationRecord,
        model: ModelRecord?,
        engine: LlamaEngine,
        context: ModelContext
    ) {
        guard let editingMessageID,
              let userIndex = sortedMessages(conversation).firstIndex(where: { $0.id == editingMessageID }) else {
            return
        }
        let sorted = sortedMessages(conversation)
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sorted[userIndex].content = trimmed
        for message in sorted.dropFirst(userIndex + 1) {
            context.delete(message)
        }
        self.editingMessageID = nil
        editingText = ""
        conversation.updatedAt = .now
        try? context.save()
        generateAssistantResponse(in: conversation, model: model, engine: engine, context: context)
    }

    func clear(conversation: ConversationRecord, context: ModelContext) {
        for message in conversation.messages {
            context.delete(message)
        }
        conversation.updatedAt = .now
        try? context.save()
    }

    private func appendAndGenerate(
        userText: String,
        in conversation: ConversationRecord,
        model: ModelRecord?,
        engine: LlamaEngine,
        context: ModelContext
    ) {
        let user = MessageRecord(role: .user, content: userText, conversation: conversation)
        conversation.messages.append(user)
        conversation.title = conversation.title == "New Chat" ? Self.title(from: userText) : conversation.title
        conversation.updatedAt = .now
        try? context.save()
        generateAssistantResponse(in: conversation, model: model, engine: engine, context: context)
    }

    private func generateAssistantResponse(
        in conversation: ConversationRecord,
        model: ModelRecord?,
        engine: LlamaEngine,
        context: ModelContext
    ) {
        guard let model else {
            errorMessage = LlamaEngineError.noModelSelected.localizedDescription
            return
        }
        guard streamTask == nil else {
            errorMessage = LlamaEngineError.generationAlreadyRunning.localizedDescription
            return
        }

        let assistant = MessageRecord(role: .assistant, content: "", conversation: conversation)
        conversation.messages.append(assistant)
        conversation.updatedAt = .now
        try? context.save()

        let history = sortedMessages(conversation)
            .filter { $0.id != assistant.id }
            .map { PromptMessage(role: $0.role, content: $0.content) }
        let metadata = ModelPromptMetadata(
            chatTemplate: model.metadata["tokenizer.chat_template"],
            bosToken: model.metadata["tokenizer.ggml.bos_token"],
            eosToken: model.metadata["tokenizer.ggml.eos_token"]
        )
        let prompt = promptBuilder.build(
            systemPrompt: conversation.systemPrompt,
            history: history,
            newUserMessage: nil,
            contextLength: conversation.generationSettings.contextLength,
            metadata: metadata
        )

        isSending = true
        streamTask = Task {
            do {
                if engine.loadedModelPath != model.localPath {
                    try await engine.loadModel(path: model.localPath, settings: conversation.generationSettings)
                }

                let start = Date()
                var finalStats = GenerationStats(tokenCount: 0, elapsedSeconds: 0, tokensPerSecond: 0)
                for try await event in engine.generate(prompt: prompt.text, settings: conversation.generationSettings) {
                    switch event {
                    case .token(let token, let count, let tps):
                        assistant.content += token
                        assistant.tokenCount = count
                        assistant.tokensPerSecond = tps
                        assistant.elapsedSeconds = Date().timeIntervalSince(start)
                        try? context.save()
                    case .completed(let stats):
                        finalStats = stats
                    }
                }
                assistant.tokenCount = finalStats.tokenCount
                assistant.tokensPerSecond = finalStats.tokensPerSecond
                assistant.elapsedSeconds = finalStats.elapsedSeconds
                conversation.updatedAt = .now
                model.lastUsedAt = .now
                try? context.save()
                engine.noteCompletedGeneration(finalStats)
            } catch {
                if assistant.content.isEmpty {
                    context.delete(assistant)
                }
                errorMessage = error.localizedDescription
                try? context.save()
            }
            streamTask = nil
            isSending = false
        }
    }

    private func sortedMessages(_ conversation: ConversationRecord) -> [MessageRecord] {
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private static func title(from text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return String(line.prefix(44))
    }
}
