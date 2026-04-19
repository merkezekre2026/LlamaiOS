import Foundation
import Combine

enum LlamaEngineState: Equatable {
    case idle
    case loading
    case ready(modelPath: String)
    case generating
    case cancelled
    case failed(String)

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}

enum GenerationEvent: Sendable, Equatable {
    case token(String, tokenCount: Int, tokensPerSecond: Double)
    case completed(GenerationStats)
}

struct GenerationStats: Sendable, Equatable {
    var tokenCount: Int
    var elapsedSeconds: Double
    var tokensPerSecond: Double
}

enum LlamaEngineError: LocalizedError, Equatable {
    case noModelSelected
    case generationAlreadyRunning
    case backendUnavailable
    case cancelled
    case bridgeFailure(String)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "Select a local GGUF model before starting a chat."
        case .generationAlreadyRunning:
            return "A response is already being generated."
        case .backendUnavailable:
            return "The llama.cpp backend is unavailable. Confirm Vendor/llama.xcframework is linked."
        case .cancelled:
            return "Generation was stopped."
        case .bridgeFailure(let message):
            return message
        }
    }
}

protocol LlamaBridgeProviding: AnyObject, Sendable {
    var isModelLoaded: Bool { get }
    func metadata(atPath path: String) throws -> [String: String]
    func loadModel(path: String, settings: GenerationSettings) throws
    func unloadModel()
    func cancel()
    func generate(
        prompt: String,
        settings: GenerationSettings,
        onToken: @escaping @Sendable (_ token: String, _ tokenCount: Int, _ tokensPerSecond: Double) -> Bool
    ) throws -> GenerationStats
}

@MainActor
final class LlamaEngine: ObservableObject {
    @Published private(set) var state: LlamaEngineState = .idle
    @Published private(set) var loadedModelPath: String?
    @Published private(set) var lastLoadTime: TimeInterval = 0
    @Published private(set) var lastGenerationStats = GenerationStats(tokenCount: 0, elapsedSeconds: 0, tokensPerSecond: 0)

    private let bridge: LlamaBridgeProviding
    private var generationTask: Task<Void, Never>?

    init(bridge: LlamaBridgeProviding = LlamaCppBridgeAdapter()) {
        self.bridge = bridge
    }

    func metadata(atPath path: String) throws -> [String: String] {
        try bridge.metadata(atPath: path)
    }

    func loadModel(path: String, settings: GenerationSettings) async throws {
        guard !state.isGenerating else {
            throw LlamaEngineError.generationAlreadyRunning
        }

        let started = Date()
        state = .loading
        let bridge = self.bridge
        do {
            try await Task.detached(priority: .userInitiated) {
                try bridge.loadModel(path: path, settings: settings.clamped())
            }.value
            loadedModelPath = path
            lastLoadTime = Date().timeIntervalSince(started)
            state = .ready(modelPath: path)
        } catch {
            let mapped = Self.map(error)
            state = .failed(mapped.localizedDescription)
            throw mapped
        }
    }

    func unloadModel() {
        stopGeneration()
        bridge.unloadModel()
        loadedModelPath = nil
        state = .idle
    }

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        bridge.cancel()
        if state.isGenerating {
            state = .cancelled
        }
    }

    func generate(prompt: String, settings: GenerationSettings) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            guard generationTask == nil else {
                continuation.finish(throwing: LlamaEngineError.generationAlreadyRunning)
                return
            }
            guard bridge.isModelLoaded else {
                continuation.finish(throwing: LlamaEngineError.noModelSelected)
                return
            }

            state = .generating
            let started = Date()
            let task = Task.detached(priority: .userInitiated) { [bridge] in
                do {
                    let stats = try bridge.generate(prompt: prompt, settings: settings.clamped()) { token, count, tps in
                        guard !Task.isCancelled else { return false }
                        continuation.yield(.token(token, tokenCount: count, tokensPerSecond: tps))
                        return true
                    }
                    let elapsed = max(Date().timeIntervalSince(started), stats.elapsedSeconds)
                    let finalStats = GenerationStats(
                        tokenCount: stats.tokenCount,
                        elapsedSeconds: elapsed,
                        tokensPerSecond: stats.tokensPerSecond
                    )
                    continuation.yield(.completed(finalStats))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }

            generationTask = task
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.generationTask?.cancel()
                    self?.generationTask = nil
                    self?.bridge.cancel()
                    if self?.state.isGenerating == true {
                        if Task.isCancelled {
                            self?.state = .cancelled
                        } else if let path = self?.loadedModelPath {
                            self?.state = .ready(modelPath: path)
                        } else {
                            self?.state = .idle
                        }
                    }
                }
            }
        }
    }

    func noteCompletedGeneration(_ stats: GenerationStats) {
        lastGenerationStats = stats
        generationTask = nil
        if let path = loadedModelPath {
            state = .ready(modelPath: path)
        } else {
            state = .idle
        }
    }

    private nonisolated static func map(_ error: Error) -> LlamaEngineError {
        if let engineError = error as? LlamaEngineError {
            return engineError
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
            return .cancelled
        }
        return .bridgeFailure(error.localizedDescription)
    }
}

final class LlamaCppBridgeAdapter: @unchecked Sendable, LlamaBridgeProviding {
    private let bridge = LlamaCppBridge()

    var isModelLoaded: Bool {
        bridge.isModelLoaded
    }

    func metadata(atPath path: String) throws -> [String: String] {
        var error: NSError?
        let metadata = bridge.readMetadata(atPath: path, error: &error)
        if let error {
            throw error
        }
        return metadata
    }

    func loadModel(path: String, settings: GenerationSettings) throws {
        try bridge.loadModel(
            atPath: path,
            contextLength: settings.contextLength,
            gpuLayers: settings.gpuLayers,
            threads: settings.threads
        )
    }

    func unloadModel() {
        bridge.unloadModel()
    }

    func cancel() {
        bridge.cancelGeneration()
    }

    func generate(
        prompt: String,
        settings: GenerationSettings,
        onToken: @escaping @Sendable (String, Int, Double) -> Bool
    ) throws -> GenerationStats {
        let parameters = LLMLlamaGenerationParameters()
        parameters.temperature = settings.temperature
        parameters.topP = settings.topP
        parameters.topK = settings.topK
        parameters.repeatPenalty = settings.repeatPenalty
        parameters.maxNewTokens = settings.maxNewTokens
        parameters.seed = settings.seed
        parameters.threads = settings.threads

        var error: NSError?
        let stats = bridge.generate(withPrompt: prompt, parameters: parameters, onToken: { token, count, tps in
            onToken(token, count, tps)
        }, error: &error)

        if let error {
            throw error
        }

        return GenerationStats(
            tokenCount: stats.tokenCount,
            elapsedSeconds: stats.elapsedSeconds,
            tokensPerSecond: stats.tokensPerSecond
        )
    }
}
