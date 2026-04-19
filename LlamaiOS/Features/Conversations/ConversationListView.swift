import SwiftData
import SwiftUI

struct ConversationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]
    @Binding var selectedID: UUID?

    var body: some View {
        List(selection: $selectedID) {
            Section {
                Button {
                    createConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .foregroundStyle(Design.accent)
            }

            Section {
                ForEach(conversations) { conversation in
                    NavigationLink(value: conversation.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .lineLimit(1)
                            Text(conversation.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(Design.secondaryText)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            delete(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("History")
            }
        }
        .navigationTitle("LlamaiOS")
        .scrollContentBackground(.hidden)
        .background(Design.background)
    }

    private func createConversation() {
        let conversation = ConversationRecord()
        modelContext.insert(conversation)
        selectedID = conversation.id
        try? modelContext.save()
    }

    private func delete(_ conversation: ConversationRecord) {
        if selectedID == conversation.id {
            selectedID = conversations.first { $0.id != conversation.id }?.id
        }
        modelContext.delete(conversation)
        try? modelContext.save()
    }
}
