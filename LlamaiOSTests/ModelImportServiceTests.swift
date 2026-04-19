import XCTest
@testable import LlamaiOS

final class ModelImportServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    func testRejectsNonGGUFExtension() throws {
        let url = tempDirectory.appendingPathComponent("model.bin")
        try Data([1, 2, 3]).write(to: url)

        XCTAssertThrowsError(try ModelImportService().validate(url: url)) { error in
            XCTAssertEqual(error as? ModelImportError, .unsupportedExtension)
        }
    }

    func testRejectsEmptyGGUFFile() throws {
        let url = tempDirectory.appendingPathComponent("empty.gguf")
        try Data().write(to: url)

        XCTAssertThrowsError(try ModelImportService().validate(url: url)) { error in
            XCTAssertEqual(error as? ModelImportError, .emptyFile)
        }
    }

    func testAcceptsReadableGGUFPath() throws {
        let url = tempDirectory.appendingPathComponent("tiny.gguf")
        try Data([0x47, 0x47, 0x55, 0x46]).write(to: url)

        let validated = try ModelImportService().validate(url: url)

        XCTAssertEqual(validated.fileName, "tiny.gguf")
        XCTAssertEqual(validated.displayName, "tiny")
        XCTAssertEqual(validated.fileSize, 4)
    }
}
