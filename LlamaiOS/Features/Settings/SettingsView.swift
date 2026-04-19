import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: LlamaEngine
    @Query private var settingsRecords: [AppSettingsRecord]
    @Query private var models: [ModelRecord]

    var body: some View {
        NavigationStack {
            List {
                if let settings = settingsRecords.first {
                    SettingsForm(settings: settings)

                    Section("Backend") {
                        LabeledContent("State", value: engineStateText)
                        LabeledContent("Active Model", value: activeModelName(settings: settings))
                        LabeledContent("Last Load", value: "\(engine.lastLoadTime, specifier: "%.2f")s")
                    }
                }

                Section {
                    NavigationLink("Privacy") { PrivacyView() }
                    NavigationLink("About") { AboutView(engine: engine) }
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Design.background)
            .onDisappear {
                try? modelContext.save()
            }
        }
    }

    private var engineStateText: String {
        switch engine.state {
        case .idle: return "Idle"
        case .loading: return "Loading"
        case .ready: return "Ready"
        case .generating: return "Generating"
        case .cancelled: return "Stopped"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private func activeModelName(settings: AppSettingsRecord) -> String {
        guard let id = settings.selectedModelID,
              let model = models.first(where: { $0.id == id }) else {
            return "None"
        }
        return model.displayName
    }
}

private struct SettingsForm: View {
    @Bindable var settings: AppSettingsRecord

    var body: some View {
        Section("Default System Prompt") {
            TextEditor(text: $settings.defaultSystemPrompt)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
        }

        Section("Generation Defaults") {
            GenerationControls(settings: $settings.generationDefaults)
        }

        Section("Interface") {
            Toggle("Show performance panel", isOn: $settings.showPerformancePanel)
            Toggle("Auto-title new chats", isOn: $settings.autoTitleChats)
        }
    }
}

private struct GenerationControls: View {
    @Binding var settings: GenerationSettings

    var body: some View {
        VStack(spacing: 12) {
            SliderRow(title: "Temperature", value: $settings.temperature, range: 0...2, format: "%.2f")
            SliderRow(title: "Top P", value: $settings.topP, range: 0.05...1, format: "%.2f")
            Stepper("Top K: \(settings.topK)", value: $settings.topK, in: 1...200)
            SliderRow(title: "Repeat Penalty", value: $settings.repeatPenalty, range: 0.8...2, format: "%.2f")
            Stepper("Max New Tokens: \(settings.maxNewTokens)", value: $settings.maxNewTokens, in: 1...4096, step: 64)
            Stepper("Context: \(settings.contextLength)", value: $settings.contextLength, in: 512...32768, step: 512)
            Stepper("Seed: \(settings.seed)", value: $settings.seed, in: -1...Int(Int32.max))
            Stepper("Threads: \(settings.threads)", value: $settings.threads, in: 1...ProcessInfo.processInfo.processorCount)
            Stepper("GPU Layers: \(settings.gpuLayers)", value: $settings.gpuLayers, in: 0...999)
        }
        .onChange(of: settings) {
            settings = settings.clamped()
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .foregroundStyle(Design.secondaryText)
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("LlamaiOS runs model loading and inference locally on device through llama.cpp. The app does not include remote inference, cloud API calls, or analytics.")
                Text("Imported GGUF models are copied into the app container so they remain available without ongoing Files access.")
            }
        }
        .navigationTitle("Privacy")
        .scrollContentBackground(.hidden)
        .background(Design.background)
    }
}

private struct AboutView: View {
    @ObservedObject var engine: LlamaEngine

    var body: some View {
        List {
            Section("App") {
                LabeledContent("Name", value: "LlamaiOS")
                LabeledContent("Version", value: "1.0")
                LabeledContent("Backend", value: "llama.cpp XCFramework")
            }
            Section("Current Session") {
                LabeledContent("Loaded Model", value: engine.loadedModelPath ?? "None")
                LabeledContent("Generated Tokens", value: "\(engine.lastGenerationStats.tokenCount)")
                LabeledContent("Tokens/sec", value: String(format: "%.1f", engine.lastGenerationStats.tokensPerSecond))
            }
        }
        .navigationTitle("About")
        .scrollContentBackground(.hidden)
        .background(Design.background)
    }
}
