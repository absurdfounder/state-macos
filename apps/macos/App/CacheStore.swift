import Foundation
import SwiftUI

enum MountMethod: String, CaseIterable, Identifiable {
    case automatic, fskit, smb
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .fskit: return "FSKit"
        case .smb: return "SMB"
        }
    }
    var detail: String {
        switch self {
        case .automatic: return "FSKit when Apple has enabled it. Otherwise a Finder volume."
        case .fskit: return "Using the FSKit file-system extension."
        case .smb: return "Drives mounted from now on use SMB."
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum DriveViewMode: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
    var title: String { self == .grid ? "Grid" : "List" }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

enum FileFilter: String, CaseIterable, Identifiable {
    case all, folders, photos, videos, documents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All items"
        case .folders: return "Folders"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .documents: return "Documents"
        }
    }

    func matches(_ item: DriveItem) -> Bool {
        switch self {
        case .all: return true
        case .folders: return item.isFolder
        case .photos: return !item.isFolder && Self.photoExts.contains(item.ext)
        case .videos: return !item.isFolder && Self.videoExts.contains(item.ext)
        case .documents: return !item.isFolder && !Self.photoExts.contains(item.ext) && !Self.videoExts.contains(item.ext)
        }
    }

    private static let photoExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]
    private static let videoExts: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]
}

enum FileSort: String, CaseIterable, Identifiable {
    case name, modified, size
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .modified: return "Date"
        case .size: return "Size"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, people, storage, billing, advanced
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .people: return "People"
        case .storage: return "Storage"
        case .billing: return "Plan & Billing"
        case .advanced: return "Advanced"
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case drive
    var id: String { rawValue }
}

enum AppPage: String, CaseIterable, Identifiable {
    case drives = "Drives"
    case storage = "Storage"
    case permissions = "Permissions"
    case account = "Account"
    case debug = "Debug"
    var id: String { rawValue }
}

enum TeamRole: String, CaseIterable, Identifiable, Codable {
    case viewer, editor, admin
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct TeamMember: Codable, Identifiable, Equatable {
    var id = UUID()
    var email: String
    var role: String

    var teamRole: TeamRole { TeamRole(rawValue: role) ?? .editor }
}

struct StorageRegionChoice: Identifiable, Equatable, Hashable {
    var code: String
    var label: String
    var id: String { code }
    var title: String { "\(label) · \(code)" }
}

enum StorageKind: String, CaseIterable, Identifiable, Codable {
    case backblaze, s3, r2, wasabi, minio, smb, folder, disk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .backblaze: return "Backblaze B2"
        case .s3: return "Amazon S3"
        case .r2: return "Cloudflare R2"
        case .wasabi: return "Wasabi"
        case .minio: return "Home server (S3 / MinIO)"
        case .smb: return "Home server (SMB)"
        case .folder: return "Folder"
        case .disk: return "Local disk"
        }
    }
    var symbol: String {
        switch self {
        case .backblaze, .s3, .r2, .wasabi, .minio: return "cloud"
        case .smb: return "externaldrive.badge.wifi"
        case .folder: return "folder"
        case .disk: return "externaldrive.connected.to.line.below"
        }
    }
    var isObjectStore: Bool { [.backblaze, .s3, .r2, .wasabi, .minio].contains(self) }
    var defaultEndpoint: String {
        switch self {
        case .backblaze: return "https://s3.us-east-005.backblazeb2.com"
        case .s3: return "https://s3.amazonaws.com"
        case .r2: return "https://<accountid>.r2.cloudflarestorage.com"
        case .wasabi: return "https://s3.wasabisys.com"
        case .minio: return "http://192.168.1.10:9000"
        default: return ""
        }
    }
    var defaultRegion: String {
        switch self {
        case .backblaze: return "us-east-005"
        case .r2: return "auto"
        default: return "us-east-1"
        }
    }
    var chipTitle: String {
        switch self {
        case .minio: return "Home S3 / MinIO"
        case .smb: return "SMB share"
        default: return title
        }
    }
    var regionChoices: [StorageRegionChoice] {
        switch self {
        case .backblaze:
            return [
                StorageRegionChoice(code: "us-east-005", label: "US East"),
                StorageRegionChoice(code: "us-west-004", label: "US West"),
                StorageRegionChoice(code: "us-west-002", label: "US West (Sacramento)"),
                StorageRegionChoice(code: "eu-central-003", label: "EU Central"),
                StorageRegionChoice(code: "us-west-000", label: "US West (000)"),
                StorageRegionChoice(code: "us-west-001", label: "US West (001)"),
            ]
        case .s3:
            return [
                StorageRegionChoice(code: "us-east-1", label: "US East (N. Virginia)"),
                StorageRegionChoice(code: "us-west-2", label: "US West (Oregon)"),
                StorageRegionChoice(code: "eu-west-1", label: "Europe (Ireland)"),
                StorageRegionChoice(code: "eu-central-1", label: "Europe (Frankfurt)"),
                StorageRegionChoice(code: "ap-southeast-1", label: "Asia Pacific (Singapore)"),
                StorageRegionChoice(code: "ap-northeast-1", label: "Asia Pacific (Tokyo)"),
            ]
        case .wasabi:
            return [
                StorageRegionChoice(code: "us-east-1", label: "US East 1"),
                StorageRegionChoice(code: "us-east-2", label: "US East 2"),
                StorageRegionChoice(code: "us-west-1", label: "US West"),
                StorageRegionChoice(code: "eu-central-1", label: "EU Central"),
                StorageRegionChoice(code: "ap-northeast-1", label: "Asia Pacific Northeast"),
            ]
        default:
            return []
        }
    }
    func endpoint(region code: String, accountId: String = "") -> String {
        switch self {
        case .backblaze:
            return "https://s3.\(code).backblazeb2.com"
        case .s3:
            return code == "us-east-1" ? "https://s3.amazonaws.com" : "https://s3.\(code).amazonaws.com"
        case .wasabi:
            return "https://s3.\(code).wasabisys.com"
        case .r2:
            let id = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? "" : "https://\(id).r2.cloudflarestorage.com"
        default:
            return defaultEndpoint
        }
    }
    var setupHint: String {
        switch self {
        case .backblaze: return "In Backblaze, create an application key with access to one bucket, then paste Key ID and Application Key here."
        case .s3: return "Use an IAM access key that can read and write this bucket."
        case .r2: return "Create an R2 API token, paste the account ID so the endpoint fills in, then the access key and secret."
        case .wasabi: return "Create an access key in the Wasabi console for this bucket."
        case .minio: return "Use your NAS or MinIO S3 endpoint, for example http://192.168.1.10:9000"
        case .smb: return "Host, share name, and login for a NAS or home server."
        default: return ""
        }
    }
    var keyIdLabel: String { self == .backblaze ? "Key ID" : "Access key ID" }
    var secretLabel: String { self == .backblaze ? "Application key" : "Secret access key" }
    var docsURL: URL? {
        switch self {
        case .backblaze: return URL(string: "https://secure.backblaze.com/app_keys.htm")
        case .s3: return URL(string: "https://console.aws.amazon.com/iam")
        case .r2: return URL(string: "https://dash.cloudflare.com/?to=/:account/r2/overview")
        case .wasabi: return URL(string: "https://console.wasabisys.com")
        default: return nil
        }
    }
    var faviconHost: String? {
        switch self {
        case .backblaze: return "backblaze.com"
        case .s3: return "aws.amazon.com"
        case .r2: return "cloudflare.com"
        case .wasabi: return "wasabi.com"
        case .minio: return "min.io"
        default: return nil
        }
    }
    var faviconURL: URL? {
        guard let host = faviconHost else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }
    var initial: String { String(title.prefix(1)) }
    var swatch: Color {
        switch self {
        case .backblaze: return Color(hex: 0xE11D48)
        case .s3: return Color(hex: 0xF59E0B)
        case .r2: return Color(hex: 0xF97316)
        case .wasabi: return Color(hex: 0x0D9488)
        case .minio: return Color(hex: 0xC2410C)
        case .smb: return Color(hex: 0x2563EB)
        case .folder, .disk: return Color(hex: 0x64748B)
        }
    }
}

struct StorageAccount: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: String
    var name: String
    var endpoint: String
    var region: String
    var bucket: String
    var accessKeyId: String
    var secretAccessKey: String
    var smbHost: String
    var smbShare: String
    var smbUser: String
    var smbPassword: String
    var createdAt: Date

    var storageKind: StorageKind { StorageKind(rawValue: kind) ?? .s3 }

    init(
        id: UUID = UUID(),
        kind: StorageKind,
        name: String,
        endpoint: String = "",
        region: String = "",
        bucket: String = "",
        accessKeyId: String = "",
        secretAccessKey: String = "",
        smbHost: String = "",
        smbShare: String = "",
        smbUser: String = "",
        smbPassword: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.name = name
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.smbHost = smbHost
        self.smbShare = smbShare
        self.smbUser = smbUser
        self.smbPassword = smbPassword
        self.createdAt = createdAt
    }

    func driveConfig() -> DriveConfig? {
        guard storageKind.isObjectStore else { return nil }
        guard !accessKeyId.isEmpty, !secretAccessKey.isEmpty, !bucket.isEmpty else { return nil }
        return DriveConfig(
            endpoint: endpoint.isEmpty ? storageKind.defaultEndpoint : endpoint,
            region: region.isEmpty ? storageKind.defaultRegion : region,
            bucket: bucket,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey
        )
    }
}

struct StorageVault: Codable, Equatable {
    var accounts: [StorageAccount] = []
    var primaryId: UUID?

    static var url: URL {
        DriveConfig.supportURL.appendingPathComponent("accounts.json")
    }

    static func load() -> StorageVault {
        guard let data = try? Data(contentsOf: url),
              let vault = try? JSONDecoder().decode(StorageVault.self, from: data) else {
            return StorageVault()
        }
        return vault
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
        }
    }

    var primary: StorageAccount? {
        if let primaryId, let match = accounts.first(where: { $0.id == primaryId }) { return match }
        return accounts.first { $0.driveConfig() != nil }
    }
}

struct LocationRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var bookmark: Data?
    var prefix: String
    var createdAt: Date
    var accountId: UUID?
    var kind: String?

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        bookmark: Data? = nil,
        prefix: String,
        createdAt: Date = Date(),
        accountId: UUID? = nil,
        kind: String? = "local"
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.prefix = prefix
        self.createdAt = createdAt
        self.accountId = accountId
        self.kind = kind
    }

    var locationKind: String { kind ?? "folder" }
    var storageKind: StorageKind {
        switch locationKind {
        case "smb": return .smb
        case "disk": return .disk
        case "cloud": return .s3
        default: return .folder
        }
    }
}

struct PinRecord: Codable, Identifiable, Equatable {
    var key: String
    var name: String
    var localPath: String
    var isFolder: Bool
    var bytes: UInt64
    var pinnedAt: Date
    var id: String { key }
}

struct DriveItem: Identifiable, Equatable, Sendable {
    var url: URL
    var name: String
    var isFolder: Bool
    var bytes: UInt64
    var modified: Date
    var id: String { url.path }
    var ext: String { url.pathExtension.lowercased() }
}

struct WorkspacePrefs: Codable, Equatable {
    var email = ""
    var workspaceName = "My Space"
    var about = ""
    var theme = AppTheme.system.rawValue
    var viewMode = DriveViewMode.grid.rawValue
    var fileFilter = FileFilter.all.rawValue
    var fileSort = FileSort.name.rawValue
    var mountMethod = MountMethod.automatic.rawValue
    var cacheLimitGB: Double = 20
    var uploadKbps: Int = 0
    var members: [TeamMember] = []
    var pins: [PinRecord] = []
    var cacheDirectory = ""
    var compression = UploadCompression.original.rawValue
    var locations: [LocationRecord] = []
    var wantMounted = true

    enum CodingKeys: String, CodingKey {
        case email, workspaceName, about, theme, viewMode, fileFilter, fileSort
        case mountMethod, cacheLimitGB, uploadKbps, members, pins, cacheDirectory, compression, locations, wantMounted
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName) ?? "My Space"
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? ""
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? AppTheme.system.rawValue
        viewMode = try c.decodeIfPresent(String.self, forKey: .viewMode) ?? DriveViewMode.grid.rawValue
        fileFilter = try c.decodeIfPresent(String.self, forKey: .fileFilter) ?? FileFilter.all.rawValue
        fileSort = try c.decodeIfPresent(String.self, forKey: .fileSort) ?? FileSort.name.rawValue
        mountMethod = try c.decodeIfPresent(String.self, forKey: .mountMethod) ?? MountMethod.automatic.rawValue
        cacheLimitGB = try c.decodeIfPresent(Double.self, forKey: .cacheLimitGB) ?? 20
        uploadKbps = try c.decodeIfPresent(Int.self, forKey: .uploadKbps) ?? 0
        members = try c.decodeIfPresent([TeamMember].self, forKey: .members) ?? []
        pins = try c.decodeIfPresent([PinRecord].self, forKey: .pins) ?? []
        cacheDirectory = try c.decodeIfPresent(String.self, forKey: .cacheDirectory) ?? ""
        compression = try c.decodeIfPresent(String.self, forKey: .compression) ?? UploadCompression.original.rawValue
        locations = try c.decodeIfPresent([LocationRecord].self, forKey: .locations) ?? []
        wantMounted = try c.decodeIfPresent(Bool.self, forKey: .wantMounted) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(email, forKey: .email)
        try c.encode(workspaceName, forKey: .workspaceName)
        try c.encode(about, forKey: .about)
        try c.encode(theme, forKey: .theme)
        try c.encode(viewMode, forKey: .viewMode)
        try c.encode(fileFilter, forKey: .fileFilter)
        try c.encode(fileSort, forKey: .fileSort)
        try c.encode(mountMethod, forKey: .mountMethod)
        try c.encode(cacheLimitGB, forKey: .cacheLimitGB)
        try c.encode(uploadKbps, forKey: .uploadKbps)
        try c.encode(members, forKey: .members)
        try c.encode(pins, forKey: .pins)
        try c.encode(cacheDirectory, forKey: .cacheDirectory)
        try c.encode(compression, forKey: .compression)
        try c.encode(locations, forKey: .locations)
        try c.encode(wantMounted, forKey: .wantMounted)
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PhotojellyFS/workspace.json")
    }

    static func load() -> WorkspacePrefs {
        guard let data = try? Data(contentsOf: url),
              let prefs = try? JSONDecoder().decode(WorkspacePrefs.self, from: data) else {
            return WorkspacePrefs()
        }
        return prefs
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.url, options: .atomic)
        }
    }
}

/// Disk + RAM cache modeled on Space: recently used blocks live under
/// `~/Library/Caches/photojellyfs`, hot blocks stay in RAM, and pinned roots
/// are full local copies that `Clear cache` will not delete.
final class CacheStore: ObservableObject {
    @Published var diskBytes: UInt64 = 0
    @Published var memoryBytes: UInt64 = 0
    @Published var blockCount: Int = 0
    @Published var previewBytes: UInt64 = 0
    let memoryCap: UInt64 = 64 * 1024 * 1024
    private let previewCap: UInt64 = 512 * 1024 * 1024
    private let memory = NSCache<NSString, NSData>()

    var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photojellyfs", isDirectory: true)
    }

    func directory(prefs: WorkspacePrefs) -> URL {
        if !prefs.cacheDirectory.isEmpty { return URL(fileURLWithPath: prefs.cacheDirectory) }
        return defaultDirectory
    }

    func pinDirectory(prefs: WorkspacePrefs) -> URL {
        directory(prefs: prefs).appendingPathComponent("pinned", isDirectory: true)
    }

    func refresh(prefs: WorkspacePrefs) {
        let root = directory(prefs: prefs)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: pinDirectory(prefs: prefs), withIntermediateDirectories: true)
        var bytes: UInt64 = 0
        var previews: UInt64 = 0
        var count = 0
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true { continue }
                let size = UInt64(values?.fileSize ?? 0)
                bytes += size
                count += 1
                if url.path.contains("/previews/") {
                    previews += size
                }
            }
        }
        diskBytes = bytes
        blockCount = count
        previewBytes = min(previews, previewCap)
        trimIfNeeded(prefs: prefs)
    }

    func clearUnpinned(prefs: WorkspacePrefs) {
        let pinned = Set(prefs.pins.map(\.key))
        let pinRoot = pinDirectory(prefs: prefs)
        let root = directory(prefs: prefs)
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let url as URL in enumerator {
                if url.path.hasPrefix(pinRoot.path) { continue }
                let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                if pinned.contains(rel) || pinned.contains(url.lastPathComponent) { continue }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
        memory.removeAllObjects()
        memoryBytes = 0
        refresh(prefs: prefs)
    }

    func remember(_ data: Data, key: String) {
        memory.setObject(data as NSData, forKey: key as NSString)
        memoryBytes = min(memoryCap, memoryBytes &+ UInt64(data.count))
    }

    func pin(file: URL, key: String, prefs: inout WorkspacePrefs) {
        let dest = pinDirectory(prefs: prefs).appendingPathComponent(key)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: file, to: dest)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
        prefs.pins.removeAll { $0.key == key }
        prefs.pins.append(
            PinRecord(
                key: key,
                name: file.lastPathComponent,
                localPath: dest.path,
                isFolder: isDir.boolValue,
                bytes: folderBytes(at: dest),
                pinnedAt: Date()
            )
        )
        prefs.save()
        refresh(prefs: prefs)
    }

    func unpin(key: String, prefs: inout WorkspacePrefs) {
        let dest = pinDirectory(prefs: prefs).appendingPathComponent(key)
        try? FileManager.default.removeItem(at: dest)
        prefs.pins.removeAll { $0.key == key }
        prefs.save()
        refresh(prefs: prefs)
    }

    private func trimIfNeeded(prefs: WorkspacePrefs) {
        let cap = UInt64(max(1, prefs.cacheLimitGB)) * 1024 * 1024 * 1024
        guard diskBytes > cap else { return }
        let pinned = Set(prefs.pins.map(\.key))
        let pinRoot = pinDirectory(prefs: prefs)
        let root = directory(prefs: prefs)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        ) else { return }
        var candidates: [(URL, Date, UInt64)] = []
        for case let url as URL in enumerator {
            if url.path.hasPrefix(pinRoot.path) { continue }
            if pinned.contains(url.lastPathComponent) { continue }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            candidates.append((url, values?.contentModificationDate ?? .distantPast, UInt64(values?.fileSize ?? 0)))
        }
        candidates.sort { $0.1 < $1.1 }
        var extra = diskBytes &- cap
        for candidate in candidates where extra > 0 {
            try? FileManager.default.removeItem(at: candidate.0)
            extra = extra > candidate.2 ? extra - candidate.2 : 0
        }
    }

    private func folderBytes(at url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values?.isDirectory != true {
            return UInt64(values?.fileSize ?? 0)
        }
        var total: UInt64 = 0
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let child as URL in enumerator {
                let childValues = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if childValues?.isDirectory == true { continue }
                total += UInt64(childValues?.fileSize ?? 0)
            }
        }
        return total
    }
}
