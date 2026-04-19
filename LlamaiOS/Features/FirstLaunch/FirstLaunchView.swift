import SwiftUI

struct FirstLaunchView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("LlamaiOS")
                        .font(.largeTitle.weight(.semibold))
                    Text("Private on-device chat for GGUF language models.")
                        .font(.title3)
                        .foregroundStyle(Design.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        HelpRow(icon: "lock.shield", title: "Local by design", detail: "Prompts, model files, and generated text stay on this iPhone.")
                        HelpRow(icon: "shippingbox", title: "Import a GGUF model", detail: "Open Models, choose a GGUF file from Files, then select it as active.")
                        HelpRow(icon: "slider.horizontal.3", title: "Tune performance", detail: "Adjust context, token limits, threads, and GPU layers per chat or in Settings.")
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sample prompts")
                            .font(.headline)
                        Text("Summarize this article in five bullets.")
                        Text("Write Swift code for a small local JSON cache.")
                        Text("Explain this error message and suggest fixes.")
                    }
                    .foregroundStyle(.white)
                    .cardStyle()
                }
                .padding(20)
            }
            .background(Design.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { dismiss() }
                }
            }
        }
    }
}

private struct HelpRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Design.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(Design.secondaryText)
            }
        }
    }
}
