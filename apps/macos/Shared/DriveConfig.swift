import Foundation

extension Notification.Name {
    static let photojellyFSDidChange = Notification.Name("com.photojelly.fs.didChange")
}

struct DriveConfig: Codable, Equatable, Sendable {
    var endpoint: String
    var region: String
    var bucket: String
    var accessKeyId: String
    var secretAccessKey: String

    static let appGroup = "group.com.photojelly.fs"
    static let fileName = "drive.json"

    var endpointURL: URL {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))!
    }

    static func load() -> DriveConfig? {
        for url in candidateURLs {
            if let data = try? Data(contentsOf: url),
               let config = try? JSONDecoder().decode(DriveConfig.self, from: data) {
                return config
            }
        }
        return nil
    }

    func save() throws {
        let url = try Self.ensureFileURL()
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static var supportURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PhotojellyFS", isDirectory: true)
    }

    static var candidateURLs: [URL] {
        var urls = [supportURL.appendingPathComponent(fileName)]
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            urls.append(container.appendingPathComponent(fileName))
        }
        return urls
    }

    static var fileURL: URL? { candidateURLs.first }

    static func ensureFileURL() throws -> URL {
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        return supportURL.appendingPathComponent(fileName)
    }


}
