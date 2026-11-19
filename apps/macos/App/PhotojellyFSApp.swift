import SwiftUI
import Darwin

@main
struct PhotojellyFSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var store = DriveStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(store)
                .photojellyTheme(store.theme)
        } label: {
            Image(systemName: store.mounted ? "externaldrive.fill" : "externaldrive")
        }
        .menuBarExtraStyle(.window)

        Window(Brand.name, id: "home") {
            HomeWindow()
                .environmentObject(store)
                .photojellyTheme(store.theme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 740)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
    }
}

enum SingleInstance {
    private static var fd: Int32 = -1

    static func claim() -> Bool {
        try? FileManager.default.createDirectory(at: VolumeMount.support, withIntermediateDirectories: true)
        let path = VolumeMount.support.appendingPathComponent("instance.lock").path
        fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            fd = -1
            return false
        }
        return true
    }

    static func activateExisting() {
        let mine = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.photojelly.mac")
            .first { $0.processIdentifier != mine }?
            .activate(options: [.activateIgnoringOtherApps])
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !SingleInstance.claim() {
            SingleInstance.activateExisting()
            exit(0)
        }
        NSApp.setActivationPolicy(.accessory)
        DriveStore.shared.boot()
        DispatchQueue.main.async {
            Self.keepOneHomeWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .photojellyOpenHome, object: nil)
        DispatchQueue.main.async { Self.keepOneHomeWindow() }
        return true
    }

    static func keepOneHomeWindow() {
        let homes = NSApp.windows.filter { $0.frame.width >= 800 }
        guard let keep = homes.first else { return }
        for extra in homes.dropFirst() {
            extra.close()
        }
        keep.makeKeyAndOrderFront(nil)
    }
}

extension Notification.Name {
    static let photojellyOpenHome = Notification.Name("com.photojelly.fs.openHome")
}
