import Foundation
import TaskerDomain

public final class SettingsRepository {
    public let layout: StorageLayout

    public init(layout: StorageLayout) throws {
        self.layout = layout
        try layout.ensureDirs()
    }

    public func load() throws -> AppSettings {
        let url = layout.settingsFile
        guard FileManager.default.fileExists(atPath: url.path) else {
            let seed = AppSettings.defaults
            try save(seed)
            return seed
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(settings)
        try FileManager.default.createDirectory(
            at: layout.root, withIntermediateDirectories: true
        )
        try data.write(to: layout.settingsFile, options: .atomic)
    }
}
