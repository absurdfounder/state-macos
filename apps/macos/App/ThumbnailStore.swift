import AppKit
import CryptoKit
import Foundation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Space keeps file previews in a separate cache (512 MiB cap). Photojelly does the same:
/// QuickLook / decoded images land in `Caches/photojellyfs/previews` so the grid can show
/// real thumbnails instead of a generic document glyph.
@MainActor
final class ThumbnailStore: ObservableObject {
    @Published private var images: [String: NSImage] = [:]
    private var loading = Set<String>()
    var directory: () -> URL

    init(directory: @escaping () -> URL) {
        self.directory = directory
    }

    func image(for item: DriveItem) -> NSImage? {
        images[item.url.path]
    }

    func prefetch(_ items: [DriveItem]) {
        for item in items.prefix(80) where !item.isFolder {
            load(item)
        }
    }

    func load(_ item: DriveItem) {
        let key = item.url.path
        guard !item.isFolder, images[key] == nil, !loading.contains(key) else { return }
        loading.insert(key)
        let url = item.url
        let disk = diskURL(for: url)
        Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: disk.path),
               let cached = NSImage(contentsOf: disk), cached.size.width > 1 {
                await MainActor.run { self.set(cached, key: key) }
                return
            }
            let generated = await Self.generate(url: url)
            if let generated {
                Self.write(generated, to: disk)
            }
            await MainActor.run { self.set(generated, key: key) }
        }
    }

    private func set(_ image: NSImage?, key: String) {
        loading.remove(key)
        if let image {
            images[key] = image
        }
    }

    private func diskURL(for file: URL) -> URL {
        let digest = SHA256.hash(data: Data(file.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = directory()
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("\(digest).jpg")
    }

    nonisolated private static func generate(url: URL) async -> NSImage? {
        if isImage(url), let loaded = NSImage(contentsOf: url), loaded.size.width > 1 {
            return resized(loaded, maxEdge: 320)
        }
        return await quickLook(url)
    }

    nonisolated private static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    nonisolated private static func quickLook(_ url: URL) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 256, height: 256),
                scale: 2,
                representationTypes: [.thumbnail, .lowQualityThumbnail, .icon]
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }

    nonisolated private static func resized(_ image: NSImage, maxEdge: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let out = NSImage(size: target)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    nonisolated private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { return }
        try? jpeg.write(to: url, options: .atomic)
    }
}
