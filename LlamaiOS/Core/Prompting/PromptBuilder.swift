import Foundation

struct PromptMessage: Equatable, Sendable {
    var role: MessageRole
    var content: String
}

struct BuiltPrompt: Equatable, Sendable {
    var text: String
    var includedMessages: [PromptMessage]
    var estimatedTokens: Int
    var wasTruncated: Bool
}

struct ModelPromptMetadata: Equatable, Sendable {
    var chatTemplate: String?
    var bosToken: String?
    var eosToken: String?
}

struct PromptBuilder {
    var tokenEstimator: TokenEstimating = HeuristicTokenEstimator()

    func build(
        systemPrompt: String,
        history: [PromptMessage],
        newUserMessage: String?,
        contextLength: Int,
        metadata: ModelPromptMetadata = .init(chatTemplate: nil, bosToken: nil, eosToken: nil)
    ) -> BuiltPrompt {
        var messages: [PromptMessage] = []
        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            messages.append(.init(role: .system, content: trimmedSystem))
        }
        messages.append(contentsOf: history.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        if let newUserMessage, !newUserMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(.init(role: .user, content: newUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        let budget = max(128, contextLength - 256)
        var truncated = false
        while tokenEstimator.estimateTokens(in: render(messages: messages, metadata: metadata)) > budget,
              messages.count > 1 {
            let removeIndex = messages.first?.role == .system ? 1 : 0
            messages.remove(at: removeIndex)
            truncated = true
        }

        let text = render(messages: messages, metadata: metadata)
        return BuiltPrompt(
            text: text,
            includedMessages: messages,
            estimatedTokens: tokenEstimator.estimateTokens(in: text),
            wasTruncated: truncated
        )
    }

    private func render(messages: [PromptMessage], metadata: ModelPromptMetadata) -> String {
        if let template = metadata.chatTemplate, !template.isEmpty {
            return renderSimpleTemplate(template, messages: messages)
        }
        return renderFallback(messages: messages, bosToken: metadata.bosToken)
    }

    private func renderFallback(messages: [PromptMessage], bosToken: String?) -> String {
        var output = bosToken ?? ""
        for message in messages {
            output += "<|im_start|>\(message.role.rawValue)\n"
            output += message.content
            output += "\n<|im_end|>\n"
        }
        output += "<|im_start|>assistant\n"
        return output
    }

    private func renderSimpleTemplate(_ template: String, messages: [PromptMessage]) -> String {
        let renderedMessages = messages.map { message in
            "<|im_start|>\(message.role.rawValue)\n\(message.content)\n<|im_end|>"
        }.joined(separator: "\n")

        if template.contains("{{ messages }}") {
            return template.replacingOccurrences(of: "{{ messages }}", with: renderedMessages)
        }
        return renderedMessages + "\n<|im_start|>assistant\n"
    }
}

protocol TokenEstimating: Sendable {
    func estimateTokens(in text: String) -> Int
}

struct HeuristicTokenEstimator: TokenEstimating {
    func estimateTokens(in text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 3.6)))
    }
}
