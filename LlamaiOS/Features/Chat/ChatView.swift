import SwiftData
import SwiftUI

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: LlamaEngine
    @Query private var models: [ModelRecord]
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var viewModel = ChatViewModel()
    @State private var showSystemPrompt = false
    @State private var autoScroll = true

    let conversation: ConversationRecord

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Design.separator)
            messageList
            composer
        }
        .background(Design.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSystemPrompt) {
            SystemPromptEditor(conversation: conversation)
        }
        .alert("LlamaiOS", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var activeModel: ModelRecord? {
        if let selected = settings.first?.selectedModelID {
            return models.first { $0.id == selected }
        }
        return models.first { $0.isSelected }
    }

    private var sortedMessages: [MessageRecord] {
        conversation.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(activeModel?.displayName ?? "No model selected")
                    .font(.caption)
                    .foregroundStyle(activeModel == nil ? Design.warning : Design.secondaryText)
            }
            Spacer()
            Button {
                showSystemPrompt = true
            } label: {
                Image(systemName: "text.badge.gearshape")
            }
            .accessibilityLabel("Edit system prompt")

            Menu {
                Button("Regenerate", systemImage: "arrow.clockwise") {
                    viewModel.regenerate(in: conversation, model: activeModel, engine: engine, context: modelContext)
                }
                Button("Edit Last User Message", systemImage: "pencil") {
                    viewModel.beginEditingLastUserMessage(in: conversation)
                }
                Button("Clear Conversation", systemImage: "trash", role: .destructive) {
                    viewModel.clear(conversation: conversation, context: modelContext)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Design.background)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if sortedMessages.isEmpty {
                        PromptSuggestions { text in
                            viewModel.draft = text
                        }
                        .padding(.top, 24)
                    }

                    ForEach(sortedMessages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .simultaneousGesture(DragGesture().onChanged { _ in autoScroll = false })
            .onChange(of: sortedMessages.last?.content) {
                guard autoScroll, let id = sortedMessages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let id = viewModel.editingMessageID {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Editing last user message")
                        .font(.caption)
                        .foregroundStyle(Design.secondaryText)
                    TextEditor(text: $viewModel.editingText)
                        .frame(minHeight: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Design.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    HStack {
                        Button("Cancel") {
                            viewModel.editingMessageID = nil
                            viewModel.editingText = ""
                        }
                        Spacer()
                        Button("Resend") {
                            viewModel.commitEdit(in: conversation, model: activeModel, engine: engine, context: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .id(id)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message LlamaiOS", text: $viewModel.draft, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Design.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit(send)

                    Button {
                        viewModel.isSending ? viewModel.stop(engine: engine) : send()
                    } label: {
                        Image(systemName: viewModel.isSending ? "stop.fill" : "arrow.up")
                            .font(.headline)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.isSending && viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if settings.first?.showPerformancePanel == true {
                PerformanceStrip(engine: engine, lastMessage: sortedMessages.last)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            viewModel.errorMessage != nil
        } set: { newValue in
            if !newValue {
                viewModel.errorMessage = nil
            }
        }
    }

    private func send() {
        autoScroll = true
        viewModel.send(in: conversation, model: activeModel, engine: engine, context: modelContext)
    }
}

private struct MessageBubble: View {
    let message: MessageRecord

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 28) }
            VStack(alignment: .leading, spacing: 8) {
                if message.role == .assistant {
                    MarkdownRenderer(text: message.content.isEmpty ? "Thinking..." : message.content)
                } else {
                    Text(message.content)
                        .textSelection(.enabled)
                }
                if message.role == .assistant, message.tokenCount > 0 {
                    Text("\(message.tokenCount) tokens · \(String(format: "%.1f", message.tokensPerSecond)) tok/s")
                        .font(.caption2)
                        .foregroundStyle(Design.secondaryText)
                }
            }
            .padding(12)
            .background(message.role == .user ? Design.userBubble : Design.assistantBubble)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 680, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 28) }
        }
    }
}

private struct PromptSuggestions: View {
    let select: (String) -> Void
    private let prompts = [
        "Explain how Metal acceleration helps local LLM inference.",
        "Draft a concise weekly plan for learning SwiftUI.",
        "Write a Swift function that validates a GGUF file URL."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask anything locally")
                .font(.title2.weight(.semibold))
            ForEach(prompts, id: \.self) { prompt in
                Button {
                    select(prompt)
                } label: {
                    HStack {
                        Text(prompt)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(12)
                    .background(Design.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PerformanceStrip: View {
    @ObservedObject var engine: LlamaEngine
    let lastMessage: MessageRecord?

    var body: some View {
        HStack(spacing: 12) {
            Label(statusText, systemImage: "cpu")
            Spacer()
            Text("\(String(format: "%.1f", lastMessage?.tokensPerSecond ?? engine.lastGenerationStats.tokensPerSecond)) tok/s")
            Text("\(String(format: "%.1f", lastMessage?.elapsedSeconds ?? engine.lastGenerationStats.elapsedSeconds))s")
        }
        .font(.caption)
        .foregroundStyle(Design.secondaryText)
    }

    private var statusText: String {
        switch engine.state {
        case .idle: return "Idle"
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .generating: return "Generating"
        case .cancelled: return "Stopped"
        case .failed: return "Failed"
        }
    }
}

private struct SystemPromptEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var conversation: ConversationRecord

    var body: some View {
        NavigationStack {
            TextEditor(text: $conversation.systemPrompt)
                .scrollContentBackground(.hidden)
                .padding()
                .background(Design.background)
                .navigationTitle("System Prompt")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            conversation.updatedAt = .now
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
        }
    }
}
