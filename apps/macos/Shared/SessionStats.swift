import Foundation

enum ByteFormat {
    static func string(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var amount = value / 1024
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return String(format: amount >= 10 ? "%.0f %@" : "%.1f %@", amount, units[index])
    }

    static func session(_ bytes: UInt64) -> String {
        if bytes == 0 { return "Zero KB this session" }
        if bytes < 1024 { return "\(bytes) bytes this session" }
        return "\(string(bytes)) this session"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1 { return "—" }
        return "\(string(UInt64(bytesPerSecond)))/s"
    }

    static func dollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func precise(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var amount = value / 1024
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        return String(format: "%.1f %@", amount, units[index])
    }
}

struct SessionStats: Codable, Equatable {
    var downloaded: UInt64 = 0
    var uploaded: UInt64 = 0
    var startedAt: Date = Date()
    var lastReadKey: String = ""
    var lastWriteKey: String = ""
    var reads: Int = 0
    var writes: Int = 0

    static let fileName = "session-stats.json"

    static var fileURL: URL? {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: DriveConfig.appGroup
        ) {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PhotojellyFS/\(fileName)")
    }

    static func load() -> SessionStats {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return SessionStats() }
        return (try? JSONDecoder().decode(SessionStats.self, from: data)) ?? SessionStats()
    }

    func save() {
        guard let url = Self.fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func record(downloaded extraDown: UInt64 = 0, uploaded extraUp: UInt64 = 0, key: String = "") {
        var stats = load()
        if extraDown > 0 {
            stats.downloaded += extraDown
            stats.reads += 1
            if !key.isEmpty { stats.lastReadKey = key }
        }
        if extraUp > 0 {
            stats.uploaded += extraUp
            stats.writes += 1
            if !key.isEmpty { stats.lastWriteKey = key }
        }
        stats.save()
    }
}
