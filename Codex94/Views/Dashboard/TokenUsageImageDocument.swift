import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TokenUsageImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data

    init(data: Data) throws {
        guard Self.isPNG(data) else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func isPNG(_ data: Data) -> Bool {
        data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) && NSBitmapImageRep(data: data) != nil
    }
}
