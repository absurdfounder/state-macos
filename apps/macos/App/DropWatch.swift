import ApplicationServices
import AppKit
import Foundation

final class DropWatch {
    private(set) var trusted = false
    private var observer: AXObserver?
    private var finderPID: pid_t = 0

    func start() {
        trusted = AXIsProcessTrusted()
        guard trusted else { return }
        watchFinder()
    }

    func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        guard trusted else { return }
        watchFinder()
    }

    private func watchFinder() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            return
        }
        finderPID = app.processIdentifier
        var created: AXObserver?
        let status = AXObserverCreate(finderPID, { _, element, notification, refcon in
            guard let refcon else { return }
            let watch = Unmanaged<DropWatch>.fromOpaque(refcon).takeUnretainedValue()
            watch.notice(element, notification: notification)
        }, &created)
        guard status == .success, let created else { return }
        observer = created
        let element = AXUIElementCreateApplication(finderPID)
        let ref = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, element, kAXCreatedNotification as CFString, ref)
        AXObserverAddNotification(created, element, kAXValueChangedNotification as CFString, ref)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    private func notice(_ element: AXUIElement, notification: CFString) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let url = value as? URL else { return }
        let mount = VolumeMount.mountPoint.path
        guard url.path == mount || url.path.hasPrefix(mount + "/") else { return }
        FinderRefresh().update(mountPoint: URL(fileURLWithPath: mount), relativeKey: "")
    }
}

struct FinderRefresh {
    func update(mountPoint: URL?, relativeKey: String) {
        guard let mountPoint else { return }
        var folder = mountPoint
        if !relativeKey.isEmpty {
            let parent = (relativeKey as NSString).deletingLastPathComponent
            if !parent.isEmpty, parent != "/" {
                folder = mountPoint.appendingPathComponent(parent)
            }
        }
        NSWorkspace.shared.noteFileSystemChanged(folder.path)
    }
}
