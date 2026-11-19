import FSKit
import Foundation
import os

@main
struct PhotojellyFSModule: UnaryFileSystemExtension {
    var fileSystem: PhotojellyFileSystem = PhotojellyFileSystem()
}

final class PhotojellyFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    private let log = Logger(subsystem: "com.photojelly.fs", category: "module")

    func didFinishLoading() {
        log.info("PhotojellyFS extension loaded")
    }

    func probeResource(resource: FSResource, replyHandler reply: @escaping (FSProbeResult?, (any Error)?) -> Void) {
        let container = FSContainerIdentifier(uuid: PhotojellyVolume.containerUUID)
        reply(FSProbeResult.usable(name: Brand.name, containerID: container), nil)
    }

    func loadResource(resource: FSResource, options: FSTaskOptions, replyHandler reply: @escaping (FSVolume?, (any Error)?) -> Void) {
        guard DriveConfig.load() != nil else {
            reply(nil, POSIXError(.ENODEV))
            return
        }
        let volume = PhotojellyVolume(
            volumeID: FSVolume.Identifier(uuid: PhotojellyVolume.containerUUID),
            volumeName: FSFileName(string: Brand.name)
        )
        reply(volume, nil)
    }

    func unloadResource(resource: FSResource, options: FSTaskOptions, replyHandler reply: @escaping ((any Error)?) -> Void) {
        reply(nil)
    }
}
