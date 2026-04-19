import Foundation

enum ModelImportError: LocalizedError, Equatable {
    case unsupportedExtension
    case unreadableFile
    case emptyFile
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension:
            return "Choose a GGUF model file."
        case .unreadableFile:
            return "The selected model could not be read. Check Files permissions and try again."
        case .emptyFile:
            return "The selected file is empty and is not a valid model."
        case .copyFailed:
            return "The model could not be copied into LlamaiOS storage."
        }
    }
}

struct ValidatedModelFile: Equatable {
    var sourceURL: URL
    var fileName: String
    var displayName: String
    var fileSize: Int64
}

struct ModelImportService {
    var fileManager: FileManager = .default

    func validate(url: URL) throws -> ValidatedModelFile {
        guard url.pathExtension.lowercased() == "gguf" else {
            throw ModelImportError.unsupportedExtension
        }

        guard fileManager.isReadableFile(atPath: url.path) else {
            throw ModelImportError.unreadableFile
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        guard size > 0 else {
            throw ModelImportError.emptyFile
        }

        let fileName = url.lastPathComponent
        return ValidatedModelFile(
            sourceURL: url,
            fileName: fileName,
            displayName: url.deletingPathExtension().lastPathComponent,
            fileSize: size
        )
    }

    func copyIntoAppStorage(url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        _ = try validate(url: url)
        let modelsDirectory = try appModelsDirectory()
        let destination = uniqueDestination(for: url.lastPathComponent, in: modelsDirectory)

        do {
            try fileManager.copyItem(at: url, to: destination)
        } catch {
            throw ModelImportError.copyFailed
        }
        return destination
    }

    func appModelsDirectory() throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func uniqueDestination(for fileName: String, in directory: URL) -> URL {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: fileName).pathExtension
        var candidate = directory.appendingPathComponent(fileName)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        return candidate
    }
}
