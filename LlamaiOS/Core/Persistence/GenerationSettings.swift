import Foundation

struct GenerationSettings: Codable, Equatable, Sendable {
    var temperature: Double
    var topP: Double
    var topK: Int
    var repeatPenalty: Double
    var maxNewTokens: Int
    var contextLength: Int
    var seed: Int
    var threads: Int
    var gpuLayers: Int

    static let `default` = GenerationSettings(
        temperature: 0.7,
        topP: 0.9,
        topK: 40,
        repeatPenalty: 1.1,
        maxNewTokens: 512,
        contextLength: 4096,
        seed: -1,
        threads: max(2, ProcessInfo.processInfo.processorCount - 2),
        gpuLayers: 99
    )

    func clamped() -> GenerationSettings {
        GenerationSettings(
            temperature: temperature.clamped(to: 0...2),
            topP: topP.clamped(to: 0.05...1),
            topK: topK.clamped(to: 1...200),
            repeatPenalty: repeatPenalty.clamped(to: 0.8...2),
            maxNewTokens: maxNewTokens.clamped(to: 1...4096),
            contextLength: contextLength.clamped(to: 512...32768),
            seed: seed,
            threads: threads.clamped(to: 1...max(1, ProcessInfo.processInfo.processorCount)),
            gpuLayers: gpuLayers.clamped(to: 0...999)
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

enum AppDefaults {
    static let systemPrompt = "You are a helpful, concise assistant running entirely on this iPhone."
}
