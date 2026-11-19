import FSKit
import Foundation
import os

final class PJItem: FSItem {
    let nodeID: UInt64
    var key: String
    var isDirectory: Bool
    var size: UInt64
    var modified: Date

    init(nodeID: UInt64, key: String, isDirectory: Bool, size: UInt64, modified: Date) {
        self.nodeID = nodeID
        self.key = key
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
        super.init()
    }
}

final class PhotojellyVolume: FSVolume, FSVolume.Operations, FSVolume.ReadWriteOperations, FSVolume.OpenCloseOperations {
    static let containerUUID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!

    private let log = Logger(subsystem: "com.photojelly.fs", category: "volume")
    private let client: B2Client
    private var items: [UInt64: PJItem] = [:]
    private var childrenCache: [String: [B2Object]] = [:]
    private var dirty: [UInt64: URL] = [:]
    private let cacheDirectory: URL
    let supportedVolumeCapabilities: FSVolume.SupportedCapabilities
    private let stats: FSStatFSResult

    override init(volumeID: FSVolume.Identifier, volumeName: FSFileName) {
        let config = DriveConfig.load()!
        self.client = B2Client(config: config)
        let caps = FSVolume.SupportedCapabilities()
        caps.supportsSymbolicLinks = false
        caps.supportsHardLinks = false
        caps.supports2TBFiles = true
        caps.supportsFastStatFS = true
        caps.supports64BitObjectIDs = true
        caps.supportsHiddenFiles = true
        caps.doesNotSupportVolumeSizes = true
        caps.caseFormat = .sensitive
        self.supportedVolumeCapabilities = caps
        self.stats = FSStatFSResult(fileSystemTypeName: "PhotojellyFS")
        self.stats.blockSize = 4096
        self.stats.ioSize = 1024 * 1024
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PhotojellyFS/cache", isDirectory: true)
        self.cacheDirectory = support
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        super.init(volumeID: volumeID, volumeName: volumeName)
        let root = PJItem(nodeID: FSItem.Identifier.rootDirectory.rawValue, key: "", isDirectory: true, size: 0, modified: Date())
        items[root.nodeID] = root
    }

    var volumeStatistics: FSStatFSResult { stats }
    var maximumLinkCount: Int { 1 }
    var maximumNameLength: Int { 255 }
    var restrictsOwnershipChanges: Bool { true }
    var truncatesLongNames: Bool { false }
    var maximumFileSize: UInt64 { 5 * 1024 * 1024 * 1024 }
    var enableOpenUnlinkEmulation: Bool { true }

    func activate(options: FSTaskOptions, replyHandler reply: @escaping (FSItem?, (any Error)?) -> Void) {
        reply(items[FSItem.Identifier.rootDirectory.rawValue], nil)
    }

    func deactivate(options: FSDeactivateOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }

    func mount(options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        log.info("Photojelly volume mounted")
        reply(nil)
    }

    func unmount(replyHandler reply: @escaping () -> Void) {
        try? flushAll()
        reply()
    }

    func synchronize(flags: FSSyncFlags, replyHandler reply: @escaping ((any Error)?) -> Void) {
        do {
            try flushAll()
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func attributes(_ desired: FSItem.GetAttributesRequest, of item: FSItem) throws -> FSItem.Attributes {
        guard let node = item as? PJItem else { throw POSIXError(.EINVAL) }
        return attributes(for: node, wanted: desired)
    }

    func getAttributes(_ desired: FSItem.GetAttributesRequest, of item: FSItem, replyHandler reply: @escaping (FSItem.Attributes?, (any Error)?) -> Void) {
        do { reply(try attributes(desired, of: item), nil) } catch { reply(nil, error) }
    }

    func setAttributes(_ newAttributes: FSItem.SetAttributesRequest, on item: FSItem, replyHandler reply: @escaping (FSItem.Attributes?, (any Error)?) -> Void) {
        guard let node = item as? PJItem else {
            reply(nil, POSIXError(.EINVAL))
            return
        }
        if newAttributes.isValid(.size), !node.isDirectory {
            node.size = newAttributes.size
            newAttributes.consumedAttributes.insert(.size)
        }
        reply(attributes(for: node, wanted: nil), nil)
    }

    func lookupItem(named name: FSFileName, inDirectory directory: FSItem, replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        guard let dir = directory as? PJItem, dir.isDirectory, let raw = name.string else {
            reply(nil, nil, POSIXError(.EINVAL))
            return
        }
        if raw == "." {
            reply(dir, name, nil)
            return
        }
        if raw == ".." {
            reply(dir, name, nil)
            return
        }
        do {
            let children = try listing(for: dir)
            guard let match = children.first(where: { $0.name == raw }) else {
                reply(nil, nil, POSIXError(.ENOENT))
                return
            }
            let item = intern(match, parentKey: dir.key)
            reply(item, FSFileName(string: match.name), nil)
        } catch {
            reply(nil, nil, error)
        }
    }

    func reclaimItem(_ item: FSItem, replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }

    func readSymbolicLink(_ item: FSItem, replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.EINVAL))
    }

    func createItem(named name: FSFileName, type: FSItem.ItemType, inDirectory directory: FSItem, attributes: FSItem.SetAttributesRequest, replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        guard let dir = directory as? PJItem, let raw = name.string, type == .file || type == .directory else {
            reply(nil, nil, POSIXError(.EINVAL))
            return
        }
        let key = join(dir.key, raw) + (type == .directory ? "/" : "")
        let object = B2Object(name: raw, key: key, isDirectory: type == .directory, size: 0, modified: Date())
        let item = intern(object, parentKey: dir.key)
        childrenCache[dir.key] = nil
        if type == .directory {
            do { try client.put(key: key, body: Data()) } catch {
                reply(nil, nil, error)
                return
            }
        } else {
            dirty[item.nodeID] = tempURL(for: item.nodeID)
        }
        reply(item, FSFileName(string: raw), nil)
    }

    func createSymbolicLink(named name: FSFileName, inDirectory directory: FSItem, attributes: FSItem.SetAttributesRequest, linkContents contents: FSFileName, replyHandler reply: @escaping (FSItem?, FSFileName?, (any Error)?) -> Void) {
        reply(nil, nil, POSIXError(.ENOTSUP))
    }

    func createLink(to item: FSItem, named name: FSFileName, inDirectory directory: FSItem, replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        reply(nil, POSIXError(.ENOTSUP))
    }

    func removeItem(_ item: FSItem, named name: FSFileName, fromDirectory directory: FSItem, replyHandler reply: @escaping ((any Error)?) -> Void) {
        guard let node = item as? PJItem, let dir = directory as? PJItem else {
            reply(POSIXError(.EINVAL))
            return
        }
        do {
            if node.isDirectory {
                let kids = try listing(for: node)
                if !kids.isEmpty { throw POSIXError(.ENOTEMPTY) }
            }
            try client.delete(key: node.key)
            dirty[node.nodeID] = nil
            childrenCache[dir.key] = nil
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func renameItem(_ item: FSItem, inDirectory sourceDirectory: FSItem, named sourceName: FSFileName, to destinationName: FSFileName, inDirectory destinationDirectory: FSItem, overItem: FSItem?, replyHandler reply: @escaping (FSFileName?, (any Error)?) -> Void) {
        guard let node = item as? PJItem,
              let source = sourceDirectory as? PJItem,
              let destination = destinationDirectory as? PJItem,
              let newName = destinationName.string else {
            reply(nil, POSIXError(.EINVAL))
            return
        }
        let newKey = join(destination.key, newName) + (node.isDirectory ? "/" : "")
        do {
            if let over = overItem as? PJItem {
                try client.delete(key: over.key)
            }
            if !node.isDirectory {
                try flush(node.nodeID)
                try client.copy(from: node.key, to: newKey)
                try client.delete(key: node.key)
            }
            node.key = newKey
            childrenCache[source.key] = nil
            childrenCache[destination.key] = nil
            reply(FSFileName(string: newName), nil)
        } catch {
            reply(nil, error)
        }
    }

    func enumerateDirectory(_ directory: FSItem, startingAt cookie: FSDirectoryCookie, verifier: FSDirectoryVerifier, attributes: FSItem.GetAttributesRequest?, packer: FSDirectoryEntryPacker, replyHandler reply: @escaping (FSDirectoryVerifier, (any Error)?) -> Void) {
        guard let dir = directory as? PJItem else {
            reply(verifier, POSIXError(.EINVAL))
            return
        }
        do {
            var entries: [(String, FSItem.ItemType, UInt64, PJItem)] = []
            if attributes == nil {
                entries.append((".", .directory, dir.nodeID, dir))
                entries.append(("..", .directory, dir.nodeID, dir))
            }
            for object in try listing(for: dir) {
                let item = intern(object, parentKey: dir.key)
                entries.append((object.name, object.isDirectory ? .directory : .file, item.nodeID, item))
            }
            let start = cookie == FSDirectoryCookie.initial ? 0 : Int(cookie.rawValue)
            guard start <= entries.count else {
                reply(verifier, POSIXError(POSIXErrorCode(rawValue: Int32(FSError.Code.invalidDirectoryCookie.rawValue)) ?? .EINVAL))
                return
            }
            for index in start..<entries.count {
                let entry = entries[index]
                let attrs = attributes == nil ? nil : self.attributes(for: entry.3, wanted: attributes)
                let keepGoing = packer.packEntry(
                    name: FSFileName(string: entry.0),
                    itemType: entry.1,
                    itemID: FSItem.Identifier(rawValue: entry.2) ?? .invalid,
                    nextCookie: FSDirectoryCookie(rawValue: UInt64(index + 1)),
                    attributes: attrs
                )
                if !keepGoing { break }
            }
            reply(FSDirectoryVerifier(rawValue: 1), nil)
        } catch {
            reply(verifier, error)
        }
    }

    func openItem(_ item: FSItem, modes: FSVolume.OpenModes, replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }

    func closeItem(_ item: FSItem, modes: FSVolume.OpenModes, replyHandler reply: @escaping ((any Error)?) -> Void) {
        guard let node = item as? PJItem else {
            reply(nil)
            return
        }
        do {
            try flush(node.nodeID)
            reply(nil)
        } catch {
            reply(error)
        }
    }

    func read(from item: FSItem, at offset: off_t, length: Int, into buffer: FSMutableFileDataBuffer, replyHandler reply: @escaping (Int, (any Error)?) -> Void) {
        guard let node = item as? PJItem, !node.isDirectory else {
            reply(0, POSIXError(.EISDIR))
            return
        }
        if offset >= Int64(node.size) || length == 0 {
            reply(0, nil)
            return
        }
        let start = Int(offset)
        let end = min(start + length, Int(node.size))
        do {
            let data: Data
            if let url = dirty[node.nodeID], FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forReadingFrom: url)
                try handle.seek(toOffset: UInt64(start))
                data = handle.readData(ofLength: end - start)
                try handle.close()
            } else {
                data = try client.get(key: node.key, range: start..<end)
            }
            try buffer.withUnsafeMutableBytes { raw in
                data.copyBytes(to: raw.bindMemory(to: UInt8.self))
            }
            SessionStats.record(downloaded: UInt64(data.count), key: node.key)
            reply(data.count, nil)
        } catch {
            reply(0, error)
        }
    }

    func write(contents: Data, to item: FSItem, at offset: off_t, replyHandler reply: @escaping (Int, (any Error)?) -> Void) {
        guard let node = item as? PJItem, !node.isDirectory else {
            reply(0, POSIXError(.EISDIR))
            return
        }
        do {
            let url = dirty[node.nodeID] ?? tempURL(for: node.nodeID)
            dirty[node.nodeID] = url
            if !FileManager.default.fileExists(atPath: url.path) {
                if node.size > 0, offset > 0 {
                    let existing = try client.get(key: node.key, range: nil)
                    try existing.write(to: url)
                } else {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seek(toOffset: UInt64(max(0, offset)))
            handle.write(contents)
            try handle.close()
            let writtenSize = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? node.size
            node.size = max(node.size, writtenSize)
            node.modified = Date()
            reply(contents.count, nil)
        } catch {
            reply(0, error)
        }
    }

    private func listing(for dir: PJItem) throws -> [B2Object] {
        if let cached = childrenCache[dir.key] { return cached }
        let prefix = dir.key.isEmpty ? "" : (dir.key.hasSuffix("/") ? dir.key : dir.key + "/")
        let listed = try client.list(prefix: prefix)
        childrenCache[dir.key] = listed
        return listed
    }

    private func intern(_ object: B2Object, parentKey: String) -> PJItem {
        let id = Self.stableID(object.key)
        if let existing = items[id] {
            existing.size = object.size
            existing.modified = object.modified
            existing.isDirectory = object.isDirectory
            existing.key = object.key
            return existing
        }
        let item = PJItem(nodeID: id, key: object.key, isDirectory: object.isDirectory, size: object.size, modified: object.modified)
        items[id] = item
        return item
    }

    private func attributes(for node: PJItem, wanted: FSItem.GetAttributesRequest?) -> FSItem.Attributes {
        let attrs = FSItem.Attributes()
        let mode: UInt32 = node.isDirectory ? 0o40755 : 0o100644
        attrs.type = node.isDirectory ? .directory : .file
        attrs.mode = mode
        attrs.linkCount = 1
        attrs.uid = getuid()
        attrs.gid = getgid()
        attrs.size = node.size
        attrs.allocSize = node.size
        attrs.fileID = FSItem.Identifier(rawValue: node.nodeID) ?? .invalid
        attrs.parentID = .rootDirectory
        var ts = timespec()
        ts.tv_sec = Int(node.modified.timeIntervalSince1970)
        attrs.modifyTime = ts
        attrs.changeTime = ts
        attrs.accessTime = ts
        attrs.birthTime = ts
        return attrs
    }

    private func flushAll() throws {
        for id in Array(dirty.keys) { try flush(id) }
    }

    private func flush(_ id: UInt64) throws {
        guard let url = dirty[id], let node = items[id] else { return }
        let data = (try? Data(contentsOf: url)) ?? Data()
        try client.put(key: node.key, body: data)
        SessionStats.record(uploaded: UInt64(data.count), key: node.key)
        node.size = UInt64(data.count)
        dirty[id] = nil
        try? FileManager.default.removeItem(at: url)
        childrenCache = [:]
        DistributedNotificationCenter.default().post(name: .photojellyFSDidChange, object: node.key)
    }

    private func tempURL(for id: UInt64) -> URL {
        cacheDirectory.appendingPathComponent("\(id).partial")
    }

    private func join(_ prefix: String, _ name: String) -> String {
        if prefix.isEmpty || prefix == "/" { return name }
        let base = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        return base + "/" + name
    }

    private static func stableID(_ key: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let id = hash & 0x0000_FFFF_FFFF_FFFF
        if id < 16 { return id + 16 }
        return id
    }
}
