import Foundation

package struct SetlistStore {
    private let url: URL

    package init(url: URL) {
        self.url = url
    }

    package func load() throws -> [SetlistEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        var entries = try JSONDecoder().decode([SetlistEntry].self, from: data)
        for index in entries.indices where entries[index].state == .playing || entries[index].state == .paused {
            entries[index].state = .queued
        }
        return entries
    }

    package func save(_ entries: [SetlistEntry], preservingSnapshot: Bool) throws -> URL? {
        try prepareDirectory()
        let data = try JSONEncoder().encode(entries)
        let backup = preservingSnapshot
            ? url.deletingPathExtension().appendingPathExtension("recovery-\(UUID().uuidString).json")
            : nil
        if let backup {
            try FileManager.default.copyItem(at: url, to: backup)
        }
        try data.write(to: url, options: .atomic)
        return backup
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
    }
}
