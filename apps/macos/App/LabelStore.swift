import Foundation

struct FileLabel: Codable, Equatable, Identifiable {
    var path: String
    var kind: String
    var scene: String
    var keep: Double
    var sensitive: Double
    var fingerprint: String
    var labeledAt: Date
    var id: String { path }

    var chips: [String] {
        [kind, scene].filter { !$0.isEmpty && $0 != "other" }
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if needle.isEmpty { return true }
        if kind.lowercased().contains(needle) { return true }
        if scene.lowercased().contains(needle) { return true }
        return chips.contains { $0.lowercased().contains(needle) }
    }
}

struct DriveSecrets: Codable, Equatable {
    var openRouterKey: String = ""

    static var url: URL {
        DriveConfig.supportURL.appendingPathComponent("secrets.json")
    }

    static func load() -> DriveSecrets {
        guard let data = try? Data(contentsOf: url),
              let secrets = try? JSONDecoder().decode(DriveSecrets.self, from: data) else {
            return DriveSecrets()
        }
        return secrets
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        }
    }

    static func resolvedKey() -> String {
        let stored = load().openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        let env = ProcessInfo.processInfo.environment
        return (env["OPENROUTER_API_KEY"] ?? env["TROOPER_OPENROUTER_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class LabelStore: ObservableObject {
    @Published var byPath: [String: FileLabel] = [:]
    @Published var searchIntent = "all"

    static var url: URL {
        DriveConfig.supportURL.appendingPathComponent("labels.json")
    }

    init() {
        load()
    }

    func label(for item: DriveItem) -> FileLabel? {
        byPath[item.url.path]
    }

    func fingerprint(for item: DriveItem) -> String {
        "\(item.name)|\(item.bytes)|\(Int(item.modified.timeIntervalSince1970))"
    }

    func needsLabel(_ item: DriveItem) -> Bool {
        if item.isFolder { return false }
        guard let existing = byPath[item.url.path] else { return true }
        return existing.fingerprint != fingerprint(for: item)
    }

    func matches(_ item: DriveItem, query: String, intent: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            if item.name.lowercased().contains(needle) { return true }
            if let label = byPath[item.url.path], label.matches(needle) { return true }
            return false
        }
        return matchesIntent(item, intent: intent)
    }

    func matchesIntent(_ item: DriveItem, intent: String) -> Bool {
        switch intent {
        case "photos": return FileFilter.photos.matches(item) || byPath[item.url.path]?.kind == "photo"
        case "videos": return FileFilter.videos.matches(item) || byPath[item.url.path]?.kind == "video"
        case "documents": return FileFilter.documents.matches(item) || byPath[item.url.path]?.kind == "document"
        case "screenshots":
            return item.name.lowercased().contains("screenshot") || byPath[item.url.path]?.kind == "screenshot"
        case "people":
            return byPath[item.url.path]?.scene == "people"
        default:
            return true
        }
    }

    func upsert(_ label: FileLabel) {
        byPath[label.path] = label
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let rows = try? JSONDecoder().decode([FileLabel].self, from: data) else { return }
        byPath = Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0) })
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rows = Array(byPath.values)
        if let data = try? JSONEncoder().encode(rows) {
            try? data.write(to: Self.url, options: .atomic)
        }
    }
}
