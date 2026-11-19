import AppKit
import ApplicationServices
import Foundation
import FSKit
import ServiceManagement

@MainActor
final class DriveStore: ObservableObject {
    static let shared = DriveStore()
    static var mountPoint: URL { VolumeMount.mountPoint }

    @Published var status = "\(Brand.name) is not mounted."
    @Published var mounted = false
    @Published var bucket = ""
    @Published var region = "us-east-005"
    @Published var endpoint = ""
    @Published var hasKeys = false
    @Published var usage: DriveUsage?
    @Published var usageError: String?
    @Published var loadingUsage = false
    @Published var accountUsage: [UUID: DriveUsage] = [:]
    @Published var locationUsage: [UUID: UInt64] = [:]
    @Published var locationCapacity: [UUID: UInt64] = [:]
    @Published var accessibility = false
    @Published var backgroundOn = false
    @Published var extensionOn = false
    @Published var onboardingDone = UserDefaults.standard.bool(forKey: "photojelly.onboarding.done.v2")
    @Published var step = 0
    @Published var accountName = NSFullUserName()
    @Published var accountEmail = ""
    @Published var session = SessionStats()
    @Published var downloadRate: Double = 0
    @Published var uploadRate: Double = 0
    @Published var updateStatus = "Up to date"
    @Published var requestedPage: AppPage?
    @Published var showSettings = false
    @Published var settingsTab: SettingsTab = .general
    @Published var sidebar: SidebarItem = .drive
    @Published var files: [DriveItem] = []
    @Published var dropping = false
    @Published var currentFolder = DriveStore.mountPoint
    @Published var selectedLocationId: UUID?
    @Published var vault = StorageVault.load()
    @Published var connectKind: StorageKind?
    @Published var showInvite = false
    @Published var storageError = ""
    @Published var inviteError = ""
    @Published var searchQuery = ""
    @Published var labeling = false
    @Published var labelStatus = ""
    @Published var labeledCount = 0
    @Published var openRouterKeyDraft = ""
    @Published var prefs = WorkspacePrefs.load()
    let cache = CacheStore()
    let labels = LabelStore()
    lazy var thumbs = ThumbnailStore { [weak self] in
        guard let self else {
            return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("photojellyfs/previews", isDirectory: true)
        }
        return self.cache.directory(prefs: self.prefs).appendingPathComponent("previews", isDirectory: true)
    }

    var mountMethod: MountMethod {
        get { MountMethod(rawValue: prefs.mountMethod) ?? .automatic }
        set { prefs.mountMethod = newValue.rawValue; prefs.save() }
    }

    var theme: AppTheme {
        get { AppTheme(rawValue: prefs.theme) ?? .system }
        set {
            var next = prefs
            next.theme = newValue.rawValue
            next.save()
            prefs = next
            newValue.applyToApp()
        }
    }

    var viewMode: DriveViewMode {
        get { DriveViewMode(rawValue: prefs.viewMode) ?? .grid }
        set { var next = prefs; next.viewMode = newValue.rawValue; next.save(); prefs = next }
    }

    var fileFilter: FileFilter {
        get { FileFilter(rawValue: prefs.fileFilter) ?? .all }
        set { var next = prefs; next.fileFilter = newValue.rawValue; next.save(); prefs = next }
    }

    var fileSort: FileSort {
        get { FileSort(rawValue: prefs.fileSort) ?? .name }
        set { var next = prefs; next.fileSort = newValue.rawValue; next.save(); prefs = next }
    }

    var visibleFiles: [DriveItem] {
        var items = files.filter { fileFilter.matches($0) }
        items = items.filter { labels.matches($0, query: searchQuery, intent: labels.searchIntent) }
        switch fileSort {
        case .name:
            items.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .modified:
            items.sort { $0.modified > $1.modified }
        case .size:
            items.sort { $0.bytes > $1.bytes }
        }
        return items
    }

    var selectedLocation: LocationRecord? {
        prefs.locations.first { $0.id == selectedLocationId }
    }

    var browseRoot: URL {
        if let location = selectedLocation, let url = resolve(location) {
            return url
        }
        return Self.mountPoint
    }

    var browseTitle: String {
        selectedLocation?.name ?? "My Drive"
    }

    var isAtRoot: Bool {
        currentFolder.standardizedFileURL.path == browseRoot.standardizedFileURL.path
    }

    var crumbs: [(name: String, url: URL)] {
        var urls: [URL] = []
        var cursor = currentFolder.standardizedFileURL
        let root = browseRoot.standardizedFileURL
        while cursor.path.hasPrefix(root.path) {
            urls.append(cursor)
            if cursor.path == root.path { break }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        return urls.reversed().map { url in
            (url.path == root.path ? browseTitle : url.lastPathComponent, url)
        }
    }

    private let drops = DropWatch()
    private var lastSession = SessionStats()
    private var lastSample = Date()
    private var statsTimer: Timer?
    private var sync: DriveSync?
    private var locationSyncs: [UUID: DriveSync] = [:]
    private var scopedURLs: [UUID: URL] = [:]
    private var didBoot = false

    func boot() {
        guard !didBoot else {
            refresh()
            refreshFiles()
            return
        }
        didBoot = true
        importConfigIfNeeded()
        accountEmail = UserDefaults.standard.string(forKey: "photojelly.account.email") ?? ""
        if accountEmail.isEmpty { accountEmail = NSUserName() }
        if prefs.email.isEmpty {
            prefs.email = accountEmail
            prefs.save()
        }
        refresh()
        cache.refresh(prefs: prefs)
        refreshFiles()
        theme.applyToApp()
        startStatsTimer()
        drops.start()
        startLocationSyncs()
        migrateLegacyConfig()
        normalizeMembers()
        ensureLoginLaunch()
        openRouterKeyDraft = DriveSecrets.resolvedKey()
        labeledCount = labels.byPath.count
        if prefs.wantMounted {
            mount(openFinder: false, userInitiated: false)
        }
        Task { await refreshExtension() }
        Task { await loadUsage() }
    }

    private func startStatsTimer() {
        guard statsTimer == nil else { return }
        lastSession = SessionStats.load()
        lastSample = Date()
        session = lastSession
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleStats() }
        }
    }

    private func sampleStats() {
        let next = SessionStats.load()
        let elapsed = max(Date().timeIntervalSince(lastSample), 0.5)
        downloadRate = Double(next.downloaded &- min(next.downloaded, lastSession.downloaded)) / elapsed
        uploadRate = Double(next.uploaded &- min(next.uploaded, lastSession.uploaded)) / elapsed
        lastSession = next
        lastSample = Date()
        session = next
    }

    func importConfigIfNeeded() {
        if let config = DriveConfig.load() {
            apply(config)
        }
        migrateLegacyConfig()
    }

    private func migrateLegacyConfig() {
        guard vault.accounts.isEmpty, let config = DriveConfig.load() else {
            if let config = primaryConfig() { apply(config) }
            return
        }
        let account = StorageAccount(
            kind: .backblaze,
            name: "Backblaze B2",
            endpoint: config.endpoint,
            region: config.region,
            bucket: config.bucket,
            accessKeyId: config.accessKeyId,
            secretAccessKey: config.secretAccessKey
        )
        vault.accounts = [account]
        vault.primaryId = account.id
        vault.save()
        apply(config)
    }

    func primaryConfig() -> DriveConfig? {
        vault.primary?.driveConfig() ?? DriveConfig.load()
    }

    func normalizeMembers() {
        var seen = Set<String>()
        let unique = prefs.members.filter { member in
            let key = member.email.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        guard unique != prefs.members else { return }
        var next = prefs
        next.members = unique
        next.save()
        prefs = next
    }

    func refresh() {
        mounted = VolumeMount.isMounted
        accessibility = AXIsProcessTrusted()
        backgroundOn = SMAppService.mainApp.status == .enabled || LoginRegistration.installed
        if mounted { status = "\(Brand.name) is in the Finder sidebar." }
    }

    func enableBackground() {
        ensureLoginLaunch()
        refresh()
    }

    private func ensureLoginLaunch() {
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            LoginRegistration.remove()
        default:
            try? LoginRegistration.install()
        }
        backgroundOn = SMAppService.mainApp.status == .enabled || LoginRegistration.installed
    }

    func promptAccessibility() {
        drops.prompt()
        refresh()
    }

    func openExtensionSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func mount(openFinder: Bool = false, userInitiated: Bool = true) {
        if userInitiated { setWantMounted(true) }
        importConfigIfNeeded()
        do {
            try attachUsingCurrentMethod()
            mounted = VolumeMount.isMounted
            NSWorkspace.shared.noteFileSystemChanged(Self.mountPoint.path)
            if let config = primaryConfig() {
                apply(config)
                status = "\(Brand.name) is in the Finder sidebar."
                startSync()
            } else {
                hasKeys = false
                status = "\(Brand.name) is in the Finder sidebar. Connect Backblaze, S3, or a local drive to sync."
            }
            if selectedLocationId == nil {
                currentFolder = Self.mountPoint
            }
            refreshFiles()
            if openFinder {
                NSWorkspace.shared.open(Self.mountPoint)
            }
        } catch {
            status = error.localizedDescription
        }
        refresh()
    }

    private func attachUsingCurrentMethod() throws {
        switch mountMethod {
        case .fskit:
            try VolumeMount.attachFSKit()
        case .smb:
            try VolumeMount.attachSMB(folder: cache.directory(prefs: prefs).appendingPathComponent("drive"))
        case .automatic:
            if extensionOn {
                do { try VolumeMount.attachFSKit(); return } catch { /* fall through */ }
            }
            try VolumeMount.attach()
        }
    }

    func applyMountMethod(_ method: MountMethod) {
        mountMethod = method
        if mounted {
            eject(userInitiated: false)
            mount(openFinder: false, userInitiated: false)
        }
    }

    func refreshFiles() {
        let root = currentFolder
        guard FileManager.default.fileExists(atPath: root.path),
              let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            files = []
            return
        }
        files = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            return DriveItem(
                url: url,
                name: url.lastPathComponent,
                isFolder: values?.isDirectory == true,
                bytes: UInt64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? Date()
            )
        }
        thumbs.prefetch(files)
        Task { await labelCurrentFolder() }
    }

    func saveOpenRouterKey() {
        var secrets = DriveSecrets.load()
        secrets.openRouterKey = openRouterKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        secrets.save()
        labelStatus = secrets.openRouterKey.isEmpty ? "OpenRouter key removed." : "OpenRouter key saved on this Mac."
    }

    func updateSearch(_ text: String) {
        searchQuery = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count < 3 {
            labels.searchIntent = "all"
            return
        }
        let key = DriveSecrets.resolvedKey()
        guard !key.isEmpty else { return }
        Task.detached { [weak self] in
            let intent = (try? JevClient.interpretSearch(query: trimmed, apiKey: key)) ?? "all"
            await MainActor.run {
                self?.labels.searchIntent = intent
            }
        }
    }

    func labelCurrentFolder() async {
        let key = DriveSecrets.resolvedKey()
        guard !key.isEmpty else { return }
        let pending = files.filter { labels.needsLabel($0) }
        guard !pending.isEmpty else {
            if !files.contains(where: { !$0.isFolder }) { return }
            labelStatus = "All files in this folder are labeled."
            return
        }
        labeling = true
        labelStatus = "Labeling \(pending.count) file\(pending.count == 1 ? "" : "s") with Jev…"
        var done = 0
        var failed = 0
        for item in pending.prefix(60) {
            let state = Self.fileState(item)
            let path = item.url.path
            let fingerprint = labels.fingerprint(for: item)
            let result: Result<JevClient.FileJudgment, Error> = await Task.detached {
                Result { try JevClient.labelFile(state: state, apiKey: key) }
            }.value
            switch result {
            case .success(let judgment):
                labels.upsert(FileLabel(
                    path: path,
                    kind: judgment.kind,
                    scene: judgment.scene,
                    keep: judgment.keep,
                    sensitive: judgment.sensitive,
                    fingerprint: fingerprint,
                    labeledAt: Date()
                ))
                labeledCount = labels.byPath.count
                done += 1
            case .failure:
                failed += 1
            }
            labelStatus = failed == 0
                ? "Labeled \(done) file\(done == 1 ? "" : "s")."
                : "Labeled \(done) file\(done == 1 ? "" : "s"). \(failed) failed."
        }
        labeling = false
    }

    nonisolated private static func fileState(_ item: DriveItem) -> String {
        let folder = item.url.deletingLastPathComponent().lastPathComponent
        return """
        name: \(item.name)
        extension: \(item.ext.isEmpty ? "none" : item.ext)
        folder: \(folder)
        bytes: \(item.bytes)
        modified: \(item.modified.formatted(.iso8601))
        is_folder: \(item.isFolder)
        """
    }

    var compression: UploadCompression {
        get { UploadCompression(rawValue: prefs.compression) ?? .original }
        set {
            var next = prefs
            next.compression = newValue.rawValue
            next.save()
            prefs = next
        }
    }

    func ingest(_ source: URL, into folder: URL? = nil) {
        if selectedLocationId == nil, !mounted { mount() }
        let dest = folder ?? currentFolder
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        _ = try? FileIngest.copy(source, into: dest, compression: compression)
        refreshFiles()
    }

    func importFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.ingest(url)
            }
        }
    }

    func openItem(_ item: DriveItem) {
        if item.isFolder {
            currentFolder = item.url
            refreshFiles()
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openRoot() {
        currentFolder = browseRoot
        refreshFiles()
    }

    func openCrumb(_ url: URL) {
        currentFolder = url
        refreshFiles()
    }

    func selectMyDrive() {
        selectedLocationId = nil
        currentFolder = Self.mountPoint
        if !mounted, prefs.wantMounted {
            mount(openFinder: false, userInitiated: false)
        }
        refreshFiles()
    }

    func selectLocation(_ location: LocationRecord) {
        selectedLocationId = location.id
        currentFolder = resolve(location) ?? URL(fileURLWithPath: location.path)
        refreshFiles()
    }

    func createFolder() {
        let name = uniqueName(NamePrompt.run(title: "New folder", message: "Name this folder.", value: "Untitled folder", button: "Create") ?? "", in: currentFolder)
        guard !name.isEmpty else { return }
        let url = currentFolder.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        markCloudFolder(url)
        refreshFiles()
    }

    func rename(_ item: DriveItem) {
        guard let next = NamePrompt.run(title: "Rename", message: "New name for \(item.name).", value: item.name, button: "Rename") else { return }
        let dest = item.url.deletingLastPathComponent().appendingPathComponent(next)
        relocate(item, to: dest)
    }

    func move(_ item: DriveItem, into folder: URL) {
        let dest = folder.appendingPathComponent(item.name)
        relocate(item, to: dest)
    }

    func deleteItem(_ item: DriveItem) {
        let alert = NSAlert()
        alert.messageText = "Delete \(item.name)?"
        alert.informativeText = item.isFolder ? "This folder and everything in it will be removed from this location and from \(Brand.name)." : "This file will be removed from this location and from \(Brand.name)."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = cloudKey(for: item.url)
        let config = primaryConfig()
        try? FileManager.default.removeItem(at: item.url)
        Task.detached {
            guard let config else { return }
            let client = B2Client(config: config)
            if item.isFolder {
                try? client.deletePrefix(key.hasSuffix("/") ? key : key + "/")
            } else {
                try? client.delete(key: key)
            }
        }
        refreshFiles()
    }

    func revealItem(_ item: DriveItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func connectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.prompt = "Connect"
        panel.message = "Pick a folder or a mounted disk. \(Brand.name) will serve it to your bucket and keep it in sync."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.connectLocation(url: url, name: url.lastPathComponent, kind: "folder")
        }
    }

    func connectDisk() {
        let disks = Self.mountedDisks()
        if disks.isEmpty {
            connectFolder()
            return
        }
        if disks.count == 1 {
            connectLocation(url: disks[0].url, name: disks[0].name, kind: "disk")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Connect a local drive"
        alert.informativeText = "\(Brand.name) will serve this disk to the bucket so it can be used like a server."
        for disk in disks {
            alert.addButton(withTitle: disk.name)
        }
        alert.addButton(withTitle: "Choose folder…")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if index >= 0, index < disks.count {
            connectLocation(url: disks[index].url, name: disks[index].name, kind: "disk")
        } else if index == disks.count {
            connectFolder()
        }
    }

    func disconnectLocation(_ location: LocationRecord) {
        locationSyncs[location.id]?.stop()
        locationSyncs[location.id] = nil
        if let url = scopedURLs.removeValue(forKey: location.id) {
            url.stopAccessingSecurityScopedResource()
        }
        var next = prefs
        next.locations.removeAll { $0.id == location.id }
        next.save()
        prefs = next
        if selectedLocationId == location.id {
            selectMyDrive()
        }
    }

    func pin(_ item: DriveItem) {
        var next = prefs
        cache.pin(file: item.url, key: cloudKey(for: item.url), prefs: &next)
        prefs = next
    }

    func isPinned(_ item: DriveItem) -> Bool {
        prefs.pins.contains { $0.localPath == item.url.path }
    }

    func togglePin(_ item: DriveItem) {
        if let pin = prefs.pins.first(where: { $0.localPath == item.url.path }) {
            unpin(pin.key)
        } else {
            pin(item)
        }
    }

    func unpin(_ key: String) {
        var next = prefs
        cache.unpin(key: key, prefs: &next)
        prefs = next
    }

    func savePrefs() {
        prefs.save()
        cache.refresh(prefs: prefs)
        theme.applyToApp()
    }

    func openBilling() {
        showSettings = true
        settingsTab = .billing
    }

    func subscribe() {
        openBilling()
        if let url = URL(string: Brand.site) {
            NSWorkspace.shared.open(url)
        }
    }

    func eject(userInitiated: Bool = true) {
        if userInitiated { setWantMounted(false) }
        sync?.stop()
        sync = nil
        VolumeMount.detach()
        refresh()
        status = mounted ? status : "\(Brand.name) was ejected."
    }

    private func setWantMounted(_ value: Bool) {
        var next = prefs
        next.wantMounted = value
        next.save()
        prefs = next
    }

    private func startSync() {
        guard let config = primaryConfig() else { return }
        sync?.stop()
        let next = DriveSync(root: Self.mountPoint, client: B2Client(config: config))
        next.onStatus = { [weak self] message in
            DispatchQueue.main.async { self?.status = message }
        }
        next.onBytes = { [weak self] _, _ in
            DispatchQueue.main.async { self?.sampleStats() }
        }
        next.onLocalChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.selectedLocationId == nil else { return }
                self.refreshFiles()
            }
        }
        next.compression = { [weak self] in
            self?.compression ?? .original
        }
        sync = next
        next.start()
    }

    func reveal() {
        NSWorkspace.shared.open(currentFolder)
    }

    func finishOnboarding() {
        onboardingDone = true
        UserDefaults.standard.set(true, forKey: "photojelly.onboarding.done.v2")
    }

    func reopenSetup() {
        onboardingDone = false
        step = 0
        UserDefaults.standard.set(false, forKey: "photojelly.onboarding.done.v2")
    }

    func checkForUpdates() {
        updateStatus = "Up to date"
    }

    func uniqueAccountName(_ base: String, excluding id: UUID? = nil) -> String {
        var names = Set(
            vault.accounts.compactMap { account -> String? in
                account.id == id ? nil : account.name
            }
        )
        for location in prefs.locations where location.accountId != id {
            names.insert(location.name)
        }
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    func loadUsage() async {
        await loadAllUsage()
    }

    func loadAllUsage() async {
        loadingUsage = true
        usageError = nil
        let accounts = vault.accounts
        let locations = prefs.locations
        struct Scan: Sendable {
            var id: UUID
            var usage: DriveUsage?
            var bytes: UInt64?
            var capacity: UInt64?
        }
        let scanned = await withTaskGroup(of: Scan.self, returning: [Scan].self) { group in
            for account in accounts {
                guard let config = account.driveConfig() else { continue }
                let id = account.id
                group.addTask {
                    do {
                        return Scan(id: id, usage: try B2Client(config: config).scan(), bytes: nil, capacity: nil)
                    } catch {
                        return Scan(id: id, usage: nil, bytes: nil, capacity: nil)
                    }
                }
            }
            for location in locations {
                let id = location.id
                let path = location.path
                let disk = location.locationKind == "disk" || location.locationKind == "smb"
                group.addTask {
                    let local = Self.localUsage(path, wholeVolume: disk)
                    return Scan(id: id, usage: nil, bytes: local.bytes, capacity: local.capacity)
                }
            }
            var rows: [Scan] = []
            for await row in group { rows.append(row) }
            return rows
        }
        var cloud: [UUID: DriveUsage] = [:]
        var local: [UUID: UInt64] = [:]
        var caps: [UUID: UInt64] = [:]
        for row in scanned {
            if let usage = row.usage { cloud[row.id] = usage }
            if let bytes = row.bytes { local[row.id] = bytes }
            if let capacity = row.capacity { caps[row.id] = capacity }
        }
        accountUsage = cloud
        locationUsage = local
        locationCapacity = caps
        let bytes = cloud.values.reduce(UInt64(0)) { $0 + $1.bytes } + local.values.reduce(0, +)
        let files = cloud.values.reduce(0) { $0 + $1.files }
        usage = DriveUsage(
            bytes: bytes,
            objectCount: files,
            folders: cloud.values.flatMap(\.folders),
            truncated: cloud.values.contains(where: \.truncated)
        )
        loadingUsage = false
    }

    nonisolated private static func localUsage(_ path: String, wholeVolume: Bool) -> (bytes: UInt64, capacity: UInt64?) {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        let capacity = values?.volumeTotalCapacity.map { UInt64(max(0, $0)) }
        if wholeVolume, let total = values?.volumeTotalCapacity {
            let available: Int
            if let important = values?.volumeAvailableCapacityForImportantUsage {
                available = Int(clamping: important)
            } else {
                available = values?.volumeAvailableCapacity ?? 0
            }
            let used = UInt64(max(0, total - available))
            return (used, capacity)
        }
        return (folderByteCount(path), capacity)
    }

    nonisolated private static func folderByteCount(_ path: String) -> UInt64 {
        if path == "/" || path.hasPrefix("/System") || path.hasPrefix("/System/Volumes") { return 0 }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return 0 }
        var total: UInt64 = 0
        var n = 0
        for case let file as URL in enumerator {
            n += 1
            if n > 80_000 { break }
            let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true { continue }
            total += UInt64(values?.fileSize ?? 0)
        }
        return total
    }

    func refreshExtension() async {
        let names = ((try? await FSClient.shared.installedExtensions) ?? []).map(\.bundleIdentifier)
        extensionOn = names.contains("com.photojelly.mac.FSExtension")
    }

    private func apply(_ config: DriveConfig) {
        bucket = config.bucket
        region = config.region
        endpoint = config.endpoint
        hasKeys = !config.accessKeyId.isEmpty && !config.secretAccessKey.isEmpty
    }

    private func connectLocation(url: URL, name: String, kind: String = "folder") {
        if url.path == Self.mountPoint.path { return }
        if prefs.locations.contains(where: { $0.path == url.path }) {
            if let existing = prefs.locations.first(where: { $0.path == url.path }) {
                selectLocation(existing)
            }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let slug = Self.slug(name)
        let prefix = uniquePrefix("locations/\(slug)/")
        let location = LocationRecord(
            name: uniqueAccountName(name),
            path: url.path,
            bookmark: bookmark,
            prefix: prefix,
            kind: kind
        )
        if scoped { scopedURLs[location.id] = url }
        var next = prefs
        next.locations.append(location)
        next.save()
        prefs = next
        startSync(for: location)
        selectLocation(location)
        status = "Serving \(location.name) to \(Brand.name)."
        Task { await loadAllUsage() }
    }

    private func startLocationSyncs() {
        for location in prefs.locations {
            startSync(for: location)
        }
    }

    private func startSync(for location: LocationRecord) {
        locationSyncs[location.id]?.stop()
        let config: DriveConfig?
        if let accountId = location.accountId {
            config = vault.accounts.first(where: { $0.id == accountId })?.driveConfig()
        } else {
            config = primaryConfig()
        }
        guard let config, let root = resolve(location) else { return }
        let next = DriveSync(root: root, client: B2Client(config: config), keyPrefix: location.prefix)
        next.onStatus = { [weak self] message in
            DispatchQueue.main.async { self?.status = message }
        }
        next.onBytes = { [weak self] _, _ in
            DispatchQueue.main.async { self?.sampleStats() }
        }
        next.onLocalChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.selectedLocationId == location.id else { return }
                self.refreshFiles()
            }
        }
        next.compression = { [weak self] in
            self?.compression ?? .original
        }
        locationSyncs[location.id] = next
        next.start()
    }

    private func resolve(_ location: LocationRecord) -> URL? {
        if let live = scopedURLs[location.id] { return live }
        if let bookmark = location.bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                scopedURLs[location.id] = url
                return url
            }
        }
        let url = URL(fileURLWithPath: location.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private func relocate(_ item: DriveItem, to dest: URL) {
        let oldKey = cloudKey(for: item.url)
        try? FileManager.default.moveItem(at: item.url, to: dest)
        let newKey = cloudKey(for: dest)
        let config = primaryConfig()
        Task.detached {
            guard let config else { return }
            let client = B2Client(config: config)
            if item.isFolder {
                try? client.relocatePrefix(from: oldKey, to: newKey)
            } else {
                try? client.copy(from: oldKey, to: newKey)
                try? client.delete(key: oldKey)
            }
        }
        if currentFolder.path == item.url.path {
            currentFolder = dest
        }
        refreshFiles()
    }

    private func markCloudFolder(_ url: URL) {
        let key = cloudKey(for: url)
        guard !key.isEmpty else { return }
        let config = primaryConfig()
        Task.detached {
            guard let config else { return }
            try? B2Client(config: config).put(key: key + "/.keep", body: Data(), contentType: "application/x-photojelly-folder")
        }
    }

    private func cloudKey(for url: URL) -> String {
        let root = browseRoot
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        let relative: String
        if path.hasPrefix(rootPath) {
            relative = String(path.dropFirst(rootPath.count))
        } else if path == root.path {
            relative = ""
        } else {
            relative = url.lastPathComponent
        }
        if let location = selectedLocation {
            return relative.isEmpty ? location.prefix : location.prefix + relative
        }
        return relative
    }

    private func uniquePrefix(_ prefix: String) -> String {
        var next = prefix
        var n = 2
        while prefs.locations.contains(where: { $0.prefix == next }) {
            next = "locations/\(Self.slug(prefix))-\(n)/"
            n += 1
        }
        return next
    }

    private func uniqueName(_ name: String, in folder: URL) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var candidate = trimmed
        var n = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
            candidate = "\(trimmed) \(n)"
            n += 1
        }
        return candidate
    }

    static func mountedDisks() -> [(name: String, url: URL)] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey, .volumeIsRootFileSystemKey],
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeIsRootFileSystemKey])
            if values?.volumeIsRootFileSystem == true { return nil }
            if url.path == "/" || url.path == Self.mountPoint.path { return nil }
            if url.path.hasPrefix("/System") { return nil }
            return (values?.volumeName ?? url.lastPathComponent, url)
        }
    }

    static func slug(_ name: String) -> String {
        let compact = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return compact.isEmpty ? "drive" : compact
    }

    func beginInvite() {
        showInvite = true
        inviteError = ""
    }

    func submitInvite(email: String, role: TeamRole) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains(".") else {
            inviteError = "Enter a valid email."
            return false
        }
        if prefs.members.contains(where: { $0.email.lowercased() == trimmed }) {
            inviteError = "\(trimmed) is already on this workspace."
            return false
        }
        var next = prefs
        next.members.append(TeamMember(email: trimmed, role: role.rawValue))
        next.save()
        prefs = next
        showInvite = false
        inviteError = ""
        status = "Invited \(trimmed) as \(role.title)."
        return true
    }

    func inviteMember() {
        beginInvite()
    }

    func setMemberRole(_ member: TeamMember, role: TeamRole) {
        var next = prefs
        if let index = next.members.firstIndex(where: { $0.id == member.id }) {
            next.members[index].role = role.rawValue
            next.save()
            prefs = next
        }
    }

    func removeMember(_ member: TeamMember) {
        var next = prefs
        next.members.removeAll { $0.id == member.id }
        next.save()
        prefs = next
    }

    func beginConnect(_ kind: StorageKind) {
        switch kind {
        case .folder: connectFolder()
        case .disk: connectDisk()
        default:
            connectKind = kind
            storageError = ""
        }
    }

    func saveStorageAccount(_ account: StorageAccount, asPrimary: Bool) {
        var account = account
        let proposed = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.name = uniqueAccountName(
            proposed.isEmpty ? account.storageKind.title : proposed,
            excluding: vault.accounts.contains(where: { $0.id == account.id }) ? account.id : nil
        )
        if let config = account.driveConfig() {
            do {
                try B2Client(config: config).probe()
            } catch {
                storageError = error.localizedDescription
                return
            }
            try? config.save()
        }
        if let index = vault.accounts.firstIndex(where: { $0.id == account.id }) {
            vault.accounts[index] = account
        } else {
            vault.accounts.append(account)
        }
        if asPrimary || vault.primaryId == nil {
            vault.primaryId = account.id
            if let config = account.driveConfig() { apply(config) }
        }
        vault.save()
        connectKind = nil
        storageError = ""
        if account.storageKind == .smb {
            connectSMBAccount(account)
        } else if asPrimary {
            if mounted {
                startSync()
            } else {
                mount(openFinder: false, userInitiated: true)
            }
            status = "\(account.name) is connected as My Drive."
        } else if let config = account.driveConfig() {
            addCloudLocation(account, config: config)
        }
        Task { await loadAllUsage() }
    }

    func makePrimary(_ account: StorageAccount) {
        vault.primaryId = account.id
        vault.save()
        if let config = account.driveConfig() {
            try? config.save()
            apply(config)
            startSync()
        }
        status = "\(account.name) is now My Drive."
    }

    func removeAccount(_ account: StorageAccount) {
        vault.accounts.removeAll { $0.id == account.id }
        if vault.primaryId == account.id {
            vault.primaryId = vault.accounts.first(where: { $0.driveConfig() != nil })?.id
            if let config = primaryConfig() {
                try? config.save()
                apply(config)
                startSync()
            }
        }
        vault.save()
        if let location = prefs.locations.first(where: { $0.accountId == account.id }) {
            disconnectLocation(location)
        }
    }

    private func addCloudLocation(_ account: StorageAccount, config: DriveConfig) {
        if !mounted {
            mount(openFinder: false, userInitiated: true)
        }
        let folder = Self.mountPoint.appendingPathComponent(account.name)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if prefs.locations.contains(where: { $0.accountId == account.id }) { return }
        let location = LocationRecord(
            name: account.name,
            path: folder.path,
            prefix: "",
            accountId: account.id,
            kind: "cloud"
        )
        var next = prefs
        next.locations.append(location)
        next.save()
        prefs = next
        startSync(for: location)
        selectLocation(location)
        status = "Connected \(account.name)."
        _ = config
    }

    private func connectSMBAccount(_ account: StorageAccount) {
        do {
            let url = try VolumeMount.attachSMBShare(
                host: account.smbHost,
                share: account.smbShare,
                user: account.smbUser,
                password: account.smbPassword
            )
            connectLocation(url: url, name: account.name.isEmpty ? account.smbShare : account.name)
            if var last = prefs.locations.last {
                last.accountId = account.id
                last.kind = "smb"
                var next = prefs
                if let index = next.locations.firstIndex(where: { $0.id == last.id }) {
                    next.locations[index] = last
                    next.save()
                    prefs = next
                }
            }
        } catch {
            storageError = error.localizedDescription
            connectKind = .smb
        }
    }

    func testStorage(_ account: StorageAccount) -> String? {
        guard let config = account.driveConfig() else {
            return "Fill in endpoint, bucket, and keys first."
        }
        do {
            try B2Client(config: config).probe()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum NamePrompt {
    static func run(title: String, message: String, value: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
