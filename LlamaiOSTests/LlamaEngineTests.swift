import XCTest
@testable import LlamaiOS

@MainActor
final class LlamaEngineTests: XCTestCase {
    func testPreventsDoubleGeneration() async throws {
        let bridge = FakeBridge()
        let engine = LlamaEngine(bridge: bridge)
        try await engine.loadModel(path: "/tmp/model.gguf", settings: .default)

        let first = engine.generate(prompt: "one", settings: .default)
        let second = engine.generate(prompt: "two", settings: .default)

        let firstTask = Task {
            var output = ""
            for try await event in first {
                if case .token(let token, _, _) = event {
                    output += token
                }
            }
            return output
        }

        do {
            for try await _ in second {}
            XCTFail("Expected second generation to fail")
        } catch {
            XCTAssertEqual(error as? LlamaEngineError, .generationAlreadyRunning)
        }

        let output = try await firstTask.value
        XCTAssertEqual(output, "abc")
    }
}

private final class FakeBridge: @unchecked Sendable, LlamaBridgeProviding {
    var isModelLoaded = false
    private var cancelled = false

    func metadata(atPath path: String) throws -> [String: String] { [:] }

    func loadModel(path: String, settings: GenerationSettings) throws {
        isModelLoaded = true
    }

    func unloadModel() {
        isModelLoaded = false
    }

    func cancel() {
        cancelled = true
    }

    func generate(
        prompt: String,
        settings: GenerationSettings,
        onToken: @escaping @Sendable (String, Int, Double) -> Bool
    ) throws -> GenerationStats {
        for (index, token) in ["a", "b", "c"].enumerated() {
            Thread.sleep(forTimeInterval: 0.05)
            if cancelled || !onToken(token, index + 1, 20) {
                throw LlamaEngineError.cancelled
            }
        }
        return GenerationStats(tokenCount: 3, elapsedSeconds: 0.15, tokensPerSecond: 20)
    }
}
