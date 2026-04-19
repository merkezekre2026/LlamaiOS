import XCTest
@testable import LlamaiOS

final class PromptBuilderTests: XCTestCase {
    func testFallbackPromptIncludesSystemHistoryAndAssistantMarker() {
        let builder = PromptBuilder(tokenEstimator: FixedEstimator(tokens: 10))
        let prompt = builder.build(
            systemPrompt: "Be concise.",
            history: [
                .init(role: .user, content: "Hello"),
                .init(role: .assistant, content: "Hi"),
                .init(role: .user, content: "Write Swift")
            ],
            newUserMessage: nil,
            contextLength: 2048
        )

        XCTAssertTrue(prompt.text.contains("<|im_start|>system\nBe concise."))
        XCTAssertTrue(prompt.text.contains("<|im_start|>user\nHello"))
        XCTAssertTrue(prompt.text.hasSuffix("<|im_start|>assistant\n"))
        XCTAssertFalse(prompt.wasTruncated)
    }

    func testTruncationPreservesSystemPromptAndNewestMessages() {
        let builder = PromptBuilder(tokenEstimator: CharacterEstimator())
        let prompt = builder.build(
            systemPrompt: "System stays",
            history: [
                .init(role: .user, content: String(repeating: "old ", count: 400)),
                .init(role: .assistant, content: String(repeating: "middle ", count: 400)),
                .init(role: .user, content: "new question")
            ],
            newUserMessage: nil,
            contextLength: 512
        )

        XCTAssertTrue(prompt.wasTruncated)
        XCTAssertEqual(prompt.includedMessages.first?.role, .system)
        XCTAssertTrue(prompt.text.contains("System stays"))
        XCTAssertTrue(prompt.text.contains("new question"))
    }

    func testSimpleTemplateReplacement() {
        let builder = PromptBuilder(tokenEstimator: FixedEstimator(tokens: 5))
        let prompt = builder.build(
            systemPrompt: "",
            history: [.init(role: .user, content: "Hi")],
            newUserMessage: nil,
            contextLength: 2048,
            metadata: .init(chatTemplate: "BEGIN\n{{ messages }}\nEND", bosToken: nil, eosToken: nil)
        )

        XCTAssertTrue(prompt.text.hasPrefix("BEGIN"))
        XCTAssertTrue(prompt.text.contains("<|im_start|>user\nHi"))
        XCTAssertTrue(prompt.text.hasSuffix("END"))
    }
}

private struct FixedEstimator: TokenEstimating {
    let tokens: Int
    func estimateTokens(in text: String) -> Int { tokens }
}

private struct CharacterEstimator: TokenEstimating {
    func estimateTokens(in text: String) -> Int { text.count }
}
