import Foundation
import SwiftData

enum MessageRole: String, Codable, CaseIterable {
    case system
    case user
    case assistant
}

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var systemPrompt: String
    var createdAt: Date
    var updatedAt: Date
    var selectedModelID: UUID?
    var temperature: Double
    var topP: Double
    var topK: Int
    var repeatPenalty: Double
    var maxNewTokens: Int
    var contextLength: Int
    var seed: Int
    var threads: Int
    var gpuLayers: Int

    @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
    var messages: [MessageRecord]

    init(
        id: UUID = UUID(),
        title: String = "New Chat",
        systemPrompt: String = AppDefaults.systemPrompt,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        selectedModelID: UUID? = nil,
        settings: GenerationSettings = .default,
        messages: [MessageRecord] = []
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.selectedModelID = selectedModelID
        self.temperature = settings.temperature
        self.topP = settings.topP
        self.topK = settings.topK
        self.repeatPenalty = settings.repeatPenalty
        self.maxNewTokens = settings.maxNewTokens
        self.contextLength = settings.contextLength
        self.seed = settings.seed
        self.threads = settings.threads
        self.gpuLayers = settings.gpuLayers
        self.messages = messages
    }

    var generationSettings: GenerationSettings {
        get {
            GenerationSettings(
                temperature: temperature,
                topP: topP,
                topK: topK,
                repeatPenalty: repeatPenalty,
                maxNewTokens: maxNewTokens,
                contextLength: contextLength,
                seed: seed,
                threads: threads,
                gpuLayers: gpuLayers
            ).clamped()
        }
        set {
            let value = newValue.clamped()
            temperature = value.temperature
            topP = value.topP
            topK = value.topK
            repeatPenalty = value.repeatPenalty
            maxNewTokens = value.maxNewTokens
            contextLength = value.contextLength
            seed = value.seed
            threads = value.threads
            gpuLayers = value.gpuLayers
        }
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var roleRawValue: String
    var content: String
    var createdAt: Date
    var tokenCount: Int
    var tokensPerSecond: Double
    var elapsedSeconds: Double
    var conversation: ConversationRecord?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = .now,
        tokenCount: Int = 0,
        tokensPerSecond: Double = 0,
        elapsedSeconds: Double = 0,
        conversation: ConversationRecord? = nil
    ) {
        self.id = id
        self.roleRawValue = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.tokenCount = tokenCount
        self.tokensPerSecond = tokensPerSecond
        self.elapsedSeconds = elapsedSeconds
        self.conversation = conversation
    }

    var role: MessageRole {
        get { MessageRole(rawValue: roleRawValue) ?? .assistant }
        set { roleRawValue = newValue.rawValue }
    }
}

@Model
final class ModelRecord {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var originalFileName: String
    var localPath: String
    var fileSize: Int64
    var importedAt: Date
    var lastUsedAt: Date?
    var isSelected: Bool
    var metadataJSON: String

    init(
        id: UUID = UUID(),
        displayName: String,
        originalFileName: String,
        localPath: String,
        fileSize: Int64,
        importedAt: Date = .now,
        lastUsedAt: Date? = nil,
        isSelected: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.originalFileName = originalFileName
        self.localPath = localPath
        self.fileSize = fileSize
        self.importedAt = importedAt
        self.lastUsedAt = lastUsedAt
        self.isSelected = isSelected
        self.metadataJSON = (try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)) ?? "{}"
    }

    var metadata: [String: String] {
        guard let data = metadataJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }
}

@Model
final class GenerationPresetRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var temperature: Double
    var topP: Double
    var topK: Int
    var repeatPenalty: Double
    var maxNewTokens: Int
    var contextLength: Int
    var seed: Int
    var threads: Int
    var gpuLayers: Int

    init(id: UUID = UUID(), name: String, settings: GenerationSettings) {
        self.id = id
        self.name = name
        self.temperature = settings.temperature
        self.topP = settings.topP
        self.topK = settings.topK
        self.repeatPenalty = settings.repeatPenalty
        self.maxNewTokens = settings.maxNewTokens
        self.contextLength = settings.contextLength
        self.seed = settings.seed
        self.threads = settings.threads
        self.gpuLayers = settings.gpuLayers
    }
}

@Model
final class AppSettingsRecord {
    @Attribute(.unique) var id: UUID
    var defaultSystemPrompt: String
    var selectedModelID: UUID?
    var hasSeenFirstLaunch: Bool
    var showPerformancePanel: Bool
    var autoTitleChats: Bool
    var defaultTemperature: Double
    var defaultTopP: Double
    var defaultTopK: Int
    var defaultRepeatPenalty: Double
    var defaultMaxNewTokens: Int
    var defaultContextLength: Int
    var defaultSeed: Int
    var defaultThreads: Int
    var defaultGPULayers: Int

    init(
        id: UUID = UUID(),
        defaultSystemPrompt: String = AppDefaults.systemPrompt,
        selectedModelID: UUID? = nil,
        hasSeenFirstLaunch: Bool = false,
        showPerformancePanel: Bool = true,
        autoTitleChats: Bool = true,
        generationDefaults: GenerationSettings = .default
    ) {
        self.id = id
        self.defaultSystemPrompt = defaultSystemPrompt
        self.selectedModelID = selectedModelID
        self.hasSeenFirstLaunch = hasSeenFirstLaunch
        self.showPerformancePanel = showPerformancePanel
        self.autoTitleChats = autoTitleChats
        self.defaultTemperature = generationDefaults.temperature
        self.defaultTopP = generationDefaults.topP
        self.defaultTopK = generationDefaults.topK
        self.defaultRepeatPenalty = generationDefaults.repeatPenalty
        self.defaultMaxNewTokens = generationDefaults.maxNewTokens
        self.defaultContextLength = generationDefaults.contextLength
        self.defaultSeed = generationDefaults.seed
        self.defaultThreads = generationDefaults.threads
        self.defaultGPULayers = generationDefaults.gpuLayers
    }

    var generationDefaults: GenerationSettings {
        get {
            GenerationSettings(
                temperature: defaultTemperature,
                topP: defaultTopP,
                topK: defaultTopK,
                repeatPenalty: defaultRepeatPenalty,
                maxNewTokens: defaultMaxNewTokens,
                contextLength: defaultContextLength,
                seed: defaultSeed,
                threads: defaultThreads,
                gpuLayers: defaultGPULayers
            ).clamped()
        }
        set {
            let value = newValue.clamped()
            defaultTemperature = value.temperature
            defaultTopP = value.topP
            defaultTopK = value.topK
            defaultRepeatPenalty = value.repeatPenalty
            defaultMaxNewTokens = value.maxNewTokens
            defaultContextLength = value.contextLength
            defaultSeed = value.seed
            defaultThreads = value.threads
            defaultGPULayers = value.gpuLayers
        }
    }
}
