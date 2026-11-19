import Foundation
import CoreServices

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return (1, error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

enum VolumeMount {
    static let name = Brand.name
    static let mountPoint = URL(fileURLWithPath: Brand.mountPath)
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PhotojellyFS", isDirectory: true)
    }
    static var imageURL: URL { support.appendingPathComponent("Photojelly.sparseimage") }

    static var isMounted: Bool {
        Shell.run("/sbin/mount", []).1.contains(mountPoint.path)
    }

    static func attach() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        detachStaleMounts()
        if !FileManager.default.fileExists(atPath: imageURL.path) {
            let created = Shell.run("/usr/bin/hdiutil", [
                "create", "-size", "200g", "-type", "SPARSE", "-fs", "APFS",
                "-volname", name, imageURL.path,
            ])
            if created.0 != 0 { throw NSError(domain: Brand.name, code: 1, userInfo: [NSLocalizedDescriptionKey: created.1]) }
        }
        if isMounted {
            renameVolumeIfNeeded()
            return
        }
        for leftover in [mountPoint.path, "/Volumes/State 1", "/Volumes/Photojelly"] {
            if FileManager.default.fileExists(atPath: leftover), !isPathMounted(leftover) {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: leftover))
            }
        }
        let attached = Shell.run("/usr/bin/hdiutil", [
            "attach", imageURL.path, "-mountpoint", mountPoint.path,
        ])
        if attached.0 != 0 || !isMounted {
            throw NSError(domain: Brand.name, code: 2, userInfo: [NSLocalizedDescriptionKey: attached.1.isEmpty ? "Could not mount \(Brand.name)." : attached.1])
        }
        renameVolumeIfNeeded()
    }

    static func detachStaleMounts() {
        for path in [mountPoint.path, "/Volumes/State 1", "/Volumes/Photojelly"] {
            if isPathMounted(path) {
                _ = Shell.run("/usr/bin/hdiutil", ["detach", path, "-force"])
            }
        }
    }

    static func renameVolumeIfNeeded() {
        _ = Shell.run("/usr/sbin/diskutil", ["rename", mountPoint.path, name])
    }

    static func attachSMBShare(host: String, share: String, user: String, password: String) throws -> URL {
        let volume = share.isEmpty ? "PhotojellyShare" : share
        let point = URL(fileURLWithPath: "/Volumes/\(volume)")
        if !isPathMounted(point.path) {
            try FileManager.default.createDirectory(at: point, withIntermediateDirectories: true)
            let userEnc = user.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? user
            let passEnc = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            let spec = password.isEmpty
                ? "//\(userEnc)@\(host)/\(share)"
                : "//\(userEnc):\(passEnc)@\(host)/\(share)"
            let mountedSMB = Shell.run("/sbin/mount_smbfs", ["-N", spec, point.path])
            if mountedSMB.0 != 0, !isPathMounted(point.path) {
                throw NSError(domain: Brand.name, code: 6, userInfo: [NSLocalizedDescriptionKey: mountedSMB.1.isEmpty ? "Could not mount the SMB share." : mountedSMB.1])
            }
        }
        return point
    }

    static func isPathMounted(_ path: String) -> Bool {
        Shell.run("/sbin/mount", []).1.contains(path)
    }

    static func detach() {
        detachStaleMounts()
        _ = Shell.run("/usr/sbin/diskutil", ["eject", name])
        _ = Shell.run("/usr/sbin/diskutil", ["eject", "Photojelly"])
        _ = Shell.run("/sbin/umount", [mountPoint.path])
        _ = Shell.run("/usr/sbin/sharing", ["-r", name])
    }

    /// Space's second Mac mount path: share the folder over SMB, then mount it as a volume.
    static func attachSMB(folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let share = Shell.run("/usr/sbin/sharing", ["-a", folder.path, "-s", name, "-g", "000"])
        if share.0 != 0 {
            let alt = Shell.run("/usr/sbin/sharing", ["-a", folder.path])
            if alt.0 != 0 {
                throw NSError(domain: Brand.name, code: 3, userInfo: [NSLocalizedDescriptionKey: "SMB share could not be created. \(share.1) \(alt.1)"])
            }
        }
        if isMounted { return }
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let mountedSMB = Shell.run("/sbin/mount_smbfs", ["-N", "//guest@localhost/\(name)", mountPoint.path])
        if mountedSMB.0 != 0, !isMounted {
            throw NSError(domain: Brand.name, code: 4, userInfo: [NSLocalizedDescriptionKey: mountedSMB.1])
        }
    }

    static func attachFSKit() throws {
        let container = support.appendingPathComponent("container", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let sentinel = container.appendingPathComponent("photojelly")
        if !FileManager.default.fileExists(atPath: sentinel.path) {
            FileManager.default.createFile(atPath: sentinel.path, contents: Data("photojelly".utf8))
        }
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let mounted = Shell.run("/sbin/mount", ["-t", "PhotojellyFS", sentinel.path, mountPoint.path])
        if mounted.0 != 0, !isMounted {
            throw NSError(domain: Brand.name, code: 5, userInfo: [NSLocalizedDescriptionKey: mounted.1.isEmpty ? "FSKit is not enabled for \(Brand.name) yet." : mounted.1])
        }
    }
}

enum LoginRegistration {
    static let agentLabel = "com.photojelly.mac"
    static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    static var installedExecutable: String {
        let candidates = [
            "/Applications/State.app/Contents/MacOS/PhotojellyFS",
            "/Applications/State.app/Contents/MacOS/State",
            "/Applications/PhotojellyFS.app/Contents/MacOS/PhotojellyFS",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[2]
    }

    static var isCurrentProcess: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == agentLabel
    }

    static func install() throws {
        let app = installedExecutable
        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [app],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: agentURL, options: .atomic)
        let domain = "gui/\(getuid())/\(agentLabel)"
        let loaded = Shell.run("/bin/launchctl", ["print", domain])
        if loaded.0 != 0 {
            _ = Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentURL.path])
            _ = Shell.run("/bin/launchctl", ["enable", domain])
        }
    }

    static func remove() {
        let domain = "gui/\(getuid())/\(agentLabel)"
        if !isCurrentProcess {
            _ = Shell.run("/bin/launchctl", ["bootout", domain])
            _ = Shell.run("/bin/launchctl", ["disable", domain])
        }
        try? FileManager.default.removeItem(at: agentURL)
    }

    static var installed: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }
}

final class DriveSync {
    private var stream: FSEventStreamRef?
    private let root: URL
    private let client: B2Client
    private let keyPrefix: String
    private var pulling = false
    var onStatus: ((String) -> Void)?
    var onBytes: ((UInt64, UInt64) -> Void)?
    var onLocalChange: (() -> Void)?
    var compression: () -> UploadCompression = { .original }

    init(root: URL, client: B2Client, keyPrefix: String = "") {
        self.root = root
        self.client = client
        self.keyPrefix = keyPrefix.hasSuffix("/") || keyPrefix.isEmpty ? keyPrefix : keyPrefix + "/"
    }

    func start() {
        pull()
        watch()
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    func pull() {
        guard !pulling else { return }
        pulling = true
        onStatus?("Reading the Backblaze bucket…")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let usage = try self.client.scan(limit: 4000)
                var downloaded: UInt64 = 0
                for object in try self.client.objects(under: self.keyPrefix) {
                    if self.keyPrefix.isEmpty, object.key.hasPrefix("locations/") { continue }
                    let relative = self.localRelative(for: object.key)
                    guard !relative.isEmpty else { continue }
                    let local = self.root.appendingPathComponent(relative)
                    if object.isDirectory {
                        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
                        continue
                    }
                    if (relative as NSString).lastPathComponent.hasPrefix(".") { continue }
                    try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let existing = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? UInt64) ?? 0
                    if FileManager.default.fileExists(atPath: local.path), existing == object.size { continue }
                    let data = try self.client.get(key: object.key, range: nil)
                    try data.write(to: local, options: .atomic)
                    downloaded += UInt64(data.count)
                    SessionStats.record(downloaded: UInt64(data.count), key: object.key)
                }
                self.onBytes?(downloaded, 0)
                self.onStatus?("\(Brand.name) is in the Finder sidebar.")
                self.onLocalChange?()
                _ = usage
            } catch {
                self.onStatus?(error.localizedDescription)
            }
            self.pulling = false
        }
    }

    private func flatten(prefix: String) throws -> [B2Object] {
        try client.objects(under: prefix)
    }

    private func localRelative(for key: String) -> String {
        if keyPrefix.isEmpty { return key }
        guard key.hasPrefix(keyPrefix) else { return "" }
        return String(key.dropFirst(keyPrefix.count))
    }

    private func watch() {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [root.path as CFString] as CFArray
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let sync = Unmanaged<DriveSync>.fromOpaque(info).takeUnretainedValue()
                let names = UnsafeRawPointer(paths).assumingMemoryBound(to: UnsafePointer<CChar>?.self)
                for index in 0..<count {
                    guard let cstr = names[Int(index)] else { continue }
                    let path = String(cString: cstr)
                    sync.changed(path: path, flag: flags[index])
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.6,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
    }

    private func changed(path: String, flag: FSEventStreamEventFlags) {
        if pulling { return }
        if path.contains(".DS_Store") || path.contains("/.") { return }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            let key = objectKey(for: path)
            if !key.isEmpty { try? client.delete(key: key) }
            return
        }
        if isDir.boolValue {
            let key = objectKey(for: path)
            if !key.isEmpty {
                try? client.put(key: key.hasSuffix("/") ? key + ".keep" : key + "/.keep", body: Data(), contentType: "application/x-photojelly-folder")
            }
            onLocalChange?()
            return
        }
        var file = url
        if let compressed = try? FileIngest.compressIfNeeded(url, compression: compression()) {
            file = compressed
        }
        let key = objectKey(for: file.path)
        guard !key.isEmpty, let data = try? Data(contentsOf: file) else { return }
        try? client.put(key: key, body: data)
        SessionStats.record(uploaded: UInt64(data.count), key: key)
        onBytes?(0, UInt64(data.count))
        onLocalChange?()
    }

    private func objectKey(for path: String) -> String {
        let rel = relative(path)
        if rel.isEmpty { return "" }
        return keyPrefix + rel
    }

    private func relative(_ path: String) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard path.hasPrefix(rootPath) else { return "" }
        return String(path.dropFirst(rootPath.count))
    }
}
