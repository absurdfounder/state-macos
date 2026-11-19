import AppKit
import Foundation
import UniformTypeIdentifiers

enum UploadCompression: String, CaseIterable, Identifiable {
    case original, compressed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Original"
        case .compressed: return "Compressed"
        }
    }
    var detail: String {
        switch self {
        case .original: return "Files are stored and uploaded exactly as they are."
        case .compressed: return "Photos are saved as JPEG before they go to Backblaze."
        }
    }
}

enum FileIngest {
    static func copy(_ source: URL, into folder: URL, compression: UploadCompression) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir)
        if isDir.boolValue {
            let dest = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let children = try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            for child in children {
                _ = try copy(child, into: dest, compression: compression)
            }
            return dest
        }
        if compression == .compressed, isImage(source) {
            return try writeJPEG(from: source, into: folder)
        }
        let dest = folder.appendingPathComponent(source.lastPathComponent)
        if dest.path != source.path {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return dest
    }

    /// Used when a file lands on the volume from Finder. Returns the URL that should be uploaded.
    static func compressIfNeeded(_ url: URL, compression: UploadCompression) throws -> URL {
        guard compression == .compressed, isImage(url), shouldRecompress(url) else { return url }
        return try writeJPEG(from: url, into: url.deletingLastPathComponent(), replacing: url)
    }

    private static func shouldRecompress(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["png", "tiff", "tif", "bmp", "heic", "heif", "webp", "gif"].contains(ext) { return true }
        if ext == "jpg" || ext == "jpeg" {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
            return size > 3 * 1024 * 1024
        }
        return false
    }

    private static func isImage(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) { return true }
        return ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp"].contains(url.pathExtension.lowercased())
    }

    private static func writeJPEG(from source: URL, into folder: URL, replacing original: URL? = nil) throws -> URL {
        guard let image = NSImage(contentsOf: source) else {
            let dest = folder.appendingPathComponent(source.lastPathComponent)
            if dest.path != source.path { try FileManager.default.copyItem(at: source, to: dest) }
            return dest
        }
        let dest = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".jpg")
        let bitmap = bitmapRep(image)
        guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else {
            throw NSError(domain: Brand.name, code: 6, userInfo: [NSLocalizedDescriptionKey: "Could not compress \(source.lastPathComponent)."])
        }
        if dest.path != source.path, FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try jpeg.write(to: dest, options: .atomic)
        if let original, original.path != dest.path {
            try? FileManager.default.removeItem(at: original)
        } else if source.path != dest.path, source.path.hasPrefix(folder.path) {
            try? FileManager.default.removeItem(at: source)
        }
        return dest
    }

    private static func bitmapRep(_ image: NSImage) -> NSBitmapImageRep {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 4096 ? 4096 / longest : 1
        let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
