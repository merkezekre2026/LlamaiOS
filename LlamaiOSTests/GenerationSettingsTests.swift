import XCTest
@testable import LlamaiOS

final class GenerationSettingsTests: XCTestCase {
    func testClampingKeepsValuesInSupportedRanges() {
        let settings = GenerationSettings(
            temperature: 5,
            topP: 0,
            topK: 999,
            repeatPenalty: 5,
            maxNewTokens: 99999,
            contextLength: 64,
            seed: 42,
            threads: 999,
            gpuLayers: -10
        ).clamped()

        XCTAssertEqual(settings.temperature, 2)
        XCTAssertEqual(settings.topP, 0.05)
        XCTAssertEqual(settings.topK, 200)
        XCTAssertEqual(settings.repeatPenalty, 2)
        XCTAssertEqual(settings.maxNewTokens, 4096)
        XCTAssertEqual(settings.contextLength, 512)
        XCTAssertEqual(settings.seed, 42)
        XCTAssertGreaterThanOrEqual(settings.threads, 1)
        XCTAssertEqual(settings.gpuLayers, 0)
    }
}
