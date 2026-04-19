import SwiftData
import SwiftUI

struct ChatRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]
    @State private var selectedID: UUID?

    var body: some View {
        NavigationSplitView {
            ConversationListView(selectedID: $selectedID)
        } detail: {
            if let conversation = selectedConversation {
                ChatView(conversation: conversation)
            } else {
                EmptyChatView(createConversation: createConversation)
            }
        }
        .onAppear {
            if conversations.isEmpty {
                createConversation()
            } else if selectedID == nil {
                selectedID = conversations.first?.id
            }
        }
    }

    private var selectedConversation: ConversationRecord? {
        conversations.first { $0.id == selectedID } ?? conversations.first
    }

    private func createConversation() {
        let conversation = ConversationRecord()
        modelContext.insert(conversation)
        try? modelContext.save()
        selectedID = conversation.id
    }
}

private struct EmptyChatView: View {
    let createConversation: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(Design.accent)
            Text("Start a local chat")
                .font(.title2.weight(.semibold))
            Text("Import a GGUF model, select it, then begin a private on-device conversation.")
                .foregroundStyle(Design.secondaryText)
                .multilineTextAlignment(.center)
            Button(action: createConversation) {
                Label("New Chat", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.background)
    }
}
