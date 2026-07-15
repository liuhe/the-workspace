import Foundation

public struct StorageLayout {
    public let root: URL

    public var tasksFile: URL { root.appendingPathComponent("tasks.jsonl") }
    public var entriesFile: URL { root.appendingPathComponent("entries.jsonl") }
    public var entriesLegacyFile: URL { root.appendingPathComponent("entries.legacy.jsonl") }
    public var descriptionsDir: URL { root.appendingPathComponent("descriptions", isDirectory: true) }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }

    public init(root: URL) {
        self.root = root
    }

    public static var `default`: StorageLayout {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return StorageLayout(root: docs.appendingPathComponent("tasker", isDirectory: true))
    }

    public func descriptionURL(for id: UUID) -> URL {
        descriptionsDir.appendingPathComponent("\(id.uuidString).md")
    }

    public func ensureDirs() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: descriptionsDir, withIntermediateDirectories: true)
    }
}
