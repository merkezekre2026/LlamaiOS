import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ModelsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var engine: LlamaEngine
    @Query(sort: \ModelRecord.importedAt, order: .reverse) private var models: [ModelRecord]
    @Query private var settings: [AppSettingsRecord]
    @StateObject private var viewModel = ModelsViewModel()
    @State private var importing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        importing = true
                    } label: {
                        Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(Design.accent)
                }

                Section("Installed") {
                    if models.isEmpty {
                        ContentUnavailableView(
                            "No Models",
                            systemImage: "shippingbox",
                            description: Text("Import a local GGUF model from Files to begin chatting.")
                        )
                        .listRowBackground(Color.clear)
                    }

                    ForEach(models) { model in
                        NavigationLink {
                            ModelDetailView(model: model)
                        } label: {
                            ModelRow(
                                model: model,
                                isActive: activeModelID == model.id
                            )
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.delete(model: model, engine: engine, context: modelContext, settings: settings.first)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                viewModel.select(model: model, allModels: models, settings: settings.first, context: modelContext)
                            } label: {
                                Label("Select", systemImage: "checkmark.circle")
                            }
                            .tint(Design.accent)
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .scrollContentBackground(.hidden)
            .background(Design.background)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importing = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.ggufModel], allowsMultipleSelection: false) { result in
                viewModel.handleImport(result: result, engine: engine, context: modelContext, settings: settings.first, existingModels: models)
            }
            .alert("Models", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var activeModelID: UUID? {
        settings.first?.selectedModelID ?? models.first(where: \.isSelected)?.id
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
}

@MainActor
final class ModelsViewModel: ObservableObject {
    @Published var errorMessage: String?
    private let importService = ModelImportService()

    func handleImport(
        result: Result<[URL], Error>,
        engine: LlamaEngine,
        context: ModelContext,
        settings: AppSettingsRecord?,
        existingModels: [ModelRecord]
    ) {
        do {
            guard let url = try result.get().first else { return }
            let copiedURL = try importService.copyIntoAppStorage(url: url)
            let validated = try importService.validate(url: copiedURL)
            let metadata = (try? engine.metadata(atPath: copiedURL.path)) ?? [:]
            let record = ModelRecord(
                displayName: metadata["general.name"] ?? validated.displayName,
                originalFileName: validated.fileName,
                localPath: copiedURL.path,
                fileSize: validated.fileSize,
                isSelected: existingModels.isEmpty,
                metadata: metadata
            )
            context.insert(record)
            if existingModels.isEmpty {
                settings?.selectedModelID = record.id
            }
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(model: ModelRecord, allModels: [ModelRecord], settings: AppSettingsRecord?, context: ModelContext) {
        for existing in allModels {
            existing.isSelected = existing.id == model.id
        }
        settings?.selectedModelID = model.id
        model.lastUsedAt = .now
        try? context.save()
    }

    func delete(model: ModelRecord, engine: LlamaEngine, context: ModelContext, settings: AppSettingsRecord?) {
        if engine.loadedModelPath == model.localPath {
            engine.unloadModel()
        }
        if settings?.selectedModelID == model.id {
            settings?.selectedModelID = nil
        }
        let path = model.localPath
        context.delete(model)
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            try context.save()
        } catch {
            errorMessage = "The model reference was removed, but the file could not be deleted: \(error.localizedDescription)"
        }
    }
}

private struct ModelRow: View {
    let model: ModelRecord
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.seal.fill" : "cube")
                .foregroundStyle(isActive ? Design.accent : Design.secondaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(Design.secondaryText)
            }
            Spacer()
        }
    }
}

private struct ModelDetailView: View {
    let model: ModelRecord

    var body: some View {
        List {
            Section("File") {
                LabeledContent("Name", value: model.displayName)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: model.fileSize, countStyle: .file))
                LabeledContent("Imported", value: model.importedAt.formatted(date: .abbreviated, time: .shortened))
                if let lastUsedAt = model.lastUsedAt {
                    LabeledContent("Last Used", value: lastUsedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Text(model.localPath)
                    .font(.caption)
                    .foregroundStyle(Design.secondaryText)
            }

            Section("Metadata") {
                if model.metadata.isEmpty {
                    Text("No metadata was exposed by llama.cpp for this model.")
                        .foregroundStyle(Design.secondaryText)
                } else {
                    ForEach(model.metadata.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key)
                                .font(.caption)
                                .foregroundStyle(Design.secondaryText)
                            Text(model.metadata[key] ?? "")
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Model Info")
        .scrollContentBackground(.hidden)
        .background(Design.background)
    }
}

extension UTType {
    static let ggufModel = UTType(filenameExtension: "gguf") ?? .data
}
