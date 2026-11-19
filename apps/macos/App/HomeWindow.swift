import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct HomeWindow: View {
    @EnvironmentObject private var store: DriveStore

    var body: some View {
        Group {
            if store.onboardingDone {
                driveShell
            } else {
                OnboardingFlow(store: store)
            }
        }
        .frame(minWidth: 1040, minHeight: 700)
        .background(PJ.canvas)
        .photojellyTheme(store.theme)
        .onAppear { store.boot() }
        .overlay {
            if store.showSettings {
                ZStack {
                    PJ.dim
                        .ignoresSafeArea()
                        .onTapGesture { store.showSettings = false }
                    SettingsSheet(store: store)
                        .frame(width: 900, height: 640)
                        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
                }
                .transition(.opacity)
            }
        }
        .animation(PJ.ease, value: store.showSettings)
        .overlay {
            if let kind = store.connectKind {
                ZStack {
                    PJ.dim
                        .ignoresSafeArea()
                        .onTapGesture { store.connectKind = nil }
                    ConnectStorageSheet(store: store, kind: kind)
                        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
                }
            }
        }
        .animation(PJ.ease, value: store.connectKind)
        .overlay {
            if store.showInvite {
                ZStack {
                    PJ.dim
                        .ignoresSafeArea()
                        .onTapGesture {
                            store.showInvite = false
                            store.inviteError = ""
                        }
                    InviteMemberSheet(store: store)
                        .shadow(color: .black.opacity(0.28), radius: 40, y: 18)
                }
            }
        }
        .animation(PJ.ease, value: store.showInvite)
        .onChange(of: store.mounted) { _, _ in store.refreshFiles() }
        .onChange(of: store.requestedPage) { _, next in
            if next != nil {
                store.showSettings = true
                store.settingsTab = next == .debug ? .advanced : .general
                store.requestedPage = nil
            }
        }
        .animation(PJ.ease, value: store.onboardingDone)
    }

    private var driveShell: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(PJ.line)
            drivePage
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PJ.tertiary)
                    .rotationEffect(.degrees(45))
                Text("Pinned")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PJ.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 36)
            .padding(.bottom, 10)

            ForEach(store.prefs.pins) { pin in
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: pin.localPath))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: pin.isFolder ? "folder.fill" : "doc")
                            .font(.system(size: 12))
                        Text(pin.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(PJ.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            HStack(spacing: 6) {
                Text("Locations")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PJ.tertiary)
                Spacer()
                Menu {
                    Button("Connect folder…", action: store.connectFolder)
                    Button("Connect disk…", action: store.connectDisk)
                    Divider()
                    Button("Backblaze B2…") { store.beginConnect(.backblaze) }
                    Button("Amazon S3…") { store.beginConnect(.s3) }
                    Button("Cloudflare R2…") { store.beginConnect(.r2) }
                    Button("Wasabi…") { store.beginConnect(.wasabi) }
                    Button("Home server (S3 / MinIO)…") { store.beginConnect(.minio) }
                    Button("Home server (SMB)…") { store.beginConnect(.smb) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PJ.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18, height: 18)
                .help("Connect drive")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 8)

            locationRow(
                title: "My Drive",
                symbol: "externaldrive.fill",
                selected: store.selectedLocationId == nil,
                mounted: store.mounted
            ) {
                store.selectMyDrive()
            } menu: {
                Button("Reveal in Finder", action: store.reveal)
                    .disabled(!store.mounted)
                Divider()
                if store.mounted {
                    Button("Eject \(Brand.name)") { store.eject() }
                } else {
                    Button("Mount \(Brand.name)") { store.mount(openFinder: true) }
                }
            }

            ForEach(store.prefs.locations) { location in
                locationRow(
                    title: location.name,
                    symbol: "externaldrive.connected.to.line.below",
                    selected: store.selectedLocationId == location.id,
                    mounted: true
                ) {
                    store.selectLocation(location)
                } menu: {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: location.path))
                    }
                    Button("Disconnect") { store.disconnectLocation(location) }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Button {
                    store.showSettings = true
                    store.settingsTab = .billing
                } label: {
                    Text("Trial — 7 days left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PJ.trialInk)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PJ.trialFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(PJ.ink)
                        Text(String(store.prefs.workspaceName.prefix(1)).uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PJ.onFilled)
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.prefs.workspaceName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PJ.ink)
                        Text(store.mounted ? "\(max(1, store.prefs.locations.count + 1)) locations" : "\(store.prefs.locations.count) local locations")
                            .font(.system(size: 11))
                            .foregroundStyle(PJ.secondary)
                    }
                    Spacer()
                    Button {
                        store.showSettings = true
                        store.settingsTab = .general
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PJ.tertiary)
                    }
                    .buttonStyle(.plain)
                    Button {
                        store.showSettings = true
                        store.settingsTab = .general
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PJ.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(width: 228)
        .background(PJ.canvas)
    }

    private var drivePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(store.browseTitle)
                .font(.system(size: 13))
                .foregroundStyle(PJ.tertiary)
                .padding(.top, 12)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            trialBanner
            header
            breadcrumbs
            if store.files.isEmpty {
                dropZone
            } else if store.visibleFiles.isEmpty {
                filterEmpty
            } else if store.viewMode == .list {
                fileList
            } else {
                fileGrid
            }
        }
        .background(PJ.canvas)
        .onDrop(of: [.fileURL], isTargeted: $store.dropping) { providers in
            importProviders(providers)
        }
    }

    private var trialBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PJ.trialInk)
            Text("7 days left in your free trial")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PJ.trialBody)
            Text("Individual access · 1 TB · No card required")
                .font(.system(size: 12))
                .foregroundStyle(PJ.trialInk.opacity(0.75))
            Spacer()
            QuietCapsule(title: "Subscribe") {
                store.subscribe()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PJ.trialFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 22)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.browseTitle)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(PJ.ink)
                Text(store.visibleFiles.count == 1 ? "1 item" : "\(store.visibleFiles.count) items")
                    .font(.system(size: 13))
                    .foregroundStyle(PJ.secondary)
                if store.labeling {
                    Text(store.labelStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(PJ.tertiary)
                } else if !store.labelStatus.isEmpty, store.searchQuery.isEmpty {
                    Text(store.labelStatus)
                        .font(.system(size: 12))
                        .foregroundStyle(PJ.tertiary)
                }
            }
            HStack(spacing: 12) {
                QuietCapsule(title: "Import", icon: "square.and.arrow.up", action: store.importFiles)
                QuietCapsule(title: "New folder", icon: "folder.badge.plus", action: store.createFolder)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PJ.tertiary)
                    TextField("Search files and labels", text: Binding(
                        get: { store.searchQuery },
                        set: { store.updateSearch($0) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(PJ.ink)
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 30)
                .background(PJ.surface, in: Capsule())
                .overlay(Capsule().stroke(PJ.line, lineWidth: 1))
                Segmented(
                    items: Array(UploadCompression.allCases),
                    title: \.title,
                    selection: Binding(
                        get: { store.compression },
                        set: { store.compression = $0 }
                    )
                )
                Spacer()
                HStack(spacing: 2) {
                    Menu {
                        Picker("Show", selection: Binding(
                            get: { store.fileFilter },
                            set: { store.fileFilter = $0 }
                        )) {
                            ForEach(FileFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        Picker("Sort", selection: Binding(
                            get: { store.fileSort },
                            set: { store.fileSort = $0 }
                        )) {
                            ForEach(FileSort.allCases) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    } label: {
                        toolbarGlyph("line.3.horizontal.decrease", active: store.fileFilter != .all || store.fileSort != .name)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 32, height: 28)
                    .help("Filter and sort")
                    Button {
                        store.viewMode = .grid
                    } label: {
                        toolbarGlyph("square.grid.2x2", active: store.viewMode == .grid)
                    }
                    .buttonStyle(.plain)
                    .help("Grid")
                    Button {
                        store.viewMode = .list
                    } label: {
                        toolbarGlyph("list.bullet", active: store.viewMode == .list)
                    }
                    .buttonStyle(.plain)
                    .help("List")
                }
                QuietCapsule(title: store.mounted ? "Upgrade to share" : "Mount drive", filled: true) {
                    if store.mounted {
                        store.subscribe()
                    } else {
                        store.mount(openFinder: true)
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            if !store.isAtRoot {
                Button {
                    store.openCrumb(store.currentFolder.deletingLastPathComponent())
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PJ.secondary)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(store.crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PJ.tertiary)
                }
                Button(crumb.name) { store.openCrumb(crumb.url) }
                    .font(.system(size: 12, weight: index == store.crumbs.count - 1 ? .semibold : .medium))
                    .foregroundStyle(index == store.crumbs.count - 1 ? PJ.ink : PJ.secondary)
                    .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 4)
    }

    private func locationRow<MenuItems: View>(
        title: String,
        symbol: String,
        selected: Bool,
        mounted: Bool,
        action: @escaping () -> Void,
        @ViewBuilder menu: () -> MenuItems
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                        .lineLimit(1)
                    Circle()
                        .fill(mounted ? Color(red: 0.18, green: 0.62, blue: 0.34) : PJ.tertiary)
                        .frame(width: 6, height: 6)
                }
                .foregroundStyle(PJ.ink)
                .padding(.leading, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu(content: menu) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PJ.tertiary)
                    .frame(width: 18, height: 32)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            Spacer(minLength: 0)
        }
        .background(selected ? PJ.fill : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.trailing, 6)
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(
                    LinearGradient(colors: [PJ.folderTop, PJ.folderBot], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
            Text("Drop files here")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PJ.ink)
            Text("Drag in files and folders, or import from your computer.")
                .font(.system(size: 13))
                .foregroundStyle(PJ.secondary)
            QuietCapsule(title: "Import", icon: "square.and.arrow.up", action: store.importFiles)
            QuietCapsule(title: "New folder", icon: "folder.badge.plus", action: store.createFolder)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(store.dropping ? PJ.drop : PJ.canvas)
    }

    private var fileGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(store.visibleFiles) { item in
                    fileCard(item)
                }
            }
            .padding(22)
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(store.visibleFiles) { item in
                    fileRow(item)
                    Rectangle().fill(PJ.line).frame(height: 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    private var filterEmpty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(PJ.tertiary)
            Text("Nothing matches this filter")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PJ.ink)
            Text("Try another filter, a search, or show all items.")
                .font(.system(size: 13))
                .foregroundStyle(PJ.secondary)
            QuietCapsule(title: "Show all") {
                store.fileFilter = .all
                store.updateSearch("")
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toolbarGlyph(_ symbol: String, active: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(active ? PJ.ink : PJ.tertiary)
            .frame(width: 32, height: 28)
            .background(active ? PJ.fill : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }

    private func fileCard(_ item: DriveItem) -> some View {
        let pinned = store.isPinned(item)
        return VStack(spacing: 8) {
            FileThumb(item: item, thumbs: store.thumbs)
            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PJ.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let chips = store.labels.label(for: item)?.chips, !chips.isEmpty {
                HStack(spacing: 4) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PJ.secondary)
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(PJ.fill, in: Capsule())
                    }
                }
            }
            Text(item.isFolder ? "Folder" : ByteFormat.string(item.bytes))
                .font(.system(size: 11))
                .foregroundStyle(PJ.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(PJ.muted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { store.openItem(item) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard item.isFolder else { return false }
            return importProviders(providers, into: item.url)
        }
        .contextMenu { itemMenu(item, pinned: pinned) }
    }

    private func fileRow(_ item: DriveItem) -> some View {
        let pinned = store.isPinned(item)
        return HStack(spacing: 12) {
            FileThumb(item: item, thumbs: store.thumbs, compact: true)
                .frame(width: 44, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PJ.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.isFolder ? "Folder" : ByteFormat.string(item.bytes))
                        .font(.system(size: 11))
                        .foregroundStyle(PJ.secondary)
                    if let chips = store.labels.label(for: item)?.chips, !chips.isEmpty {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(PJ.tertiary)
                        }
                    }
                }
            }
            Spacer()
            Text(item.modified.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 12))
                .foregroundStyle(PJ.tertiary)
            if pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(PJ.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { store.openItem(item) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard item.isFolder else { return false }
            return importProviders(providers, into: item.url)
        }
        .contextMenu { itemMenu(item, pinned: pinned) }
    }

    @ViewBuilder
    private func itemMenu(_ item: DriveItem, pinned: Bool) -> some View {
        Button("Open") { store.openItem(item) }
        Button("Show in Finder") { store.revealItem(item) }
        Button("Label with Jev") {
            Task { await store.labelCurrentFolder() }
        }
        .disabled(item.isFolder || DriveSecrets.resolvedKey().isEmpty)
        Divider()
        Button("Rename…") { store.rename(item) }
        Menu("Move to") {
            ForEach(store.files.filter { $0.isFolder && $0.url != item.url }) { folder in
                Button(folder.name) { store.move(item, into: folder.url) }
            }
            Button("Choose folder…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.directoryURL = store.browseRoot
                panel.begin { response in
                    guard response == .OK, let url = panel.url else { return }
                    store.move(item, into: url)
                }
            }
        }
        Button(pinned ? "Unpin" : "Keep offline") { store.togglePin(item) }
        Divider()
        Button("Delete…", role: .destructive) { store.deleteItem(item) }
    }

    private func importProviders(_ providers: [NSItemProvider], into folder: URL? = nil) -> Bool {
        if store.selectedLocationId == nil, !store.mounted { store.mount() }
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL? = {
                    if let url = item as? URL { return url }
                    if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
                    return nil
                }()
                guard let url else { return }
                DispatchQueue.main.async {
                    if let folder, url.path.hasPrefix(store.browseRoot.path), url.path != folder.path {
                        store.move(
                            DriveItem(url: url, name: url.lastPathComponent, isFolder: url.hasDirectoryPath, bytes: 0, modified: Date()),
                            into: folder
                        )
                    } else {
                        store.ingest(url, into: folder)
                    }
                }
            }
        }
        return true
    }
}

private struct FileThumb: View {
    let item: DriveItem
    @ObservedObject var thumbs: ThumbnailStore
    var compact = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PJ.surface)
            if item.isFolder {
                Image(systemName: "folder.fill")
                    .font(.system(size: compact ? 18 : 36))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: 0x93C5FD), Color(hex: 0x60A5FA)], startPoint: .top, endPoint: .bottom)
                    )
            } else if let image = thumbs.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fileSymbol(item.name))
                    .font(.system(size: compact ? 16 : 32, weight: .regular))
                    .foregroundStyle(PJ.tertiary)
            }
        }
        .frame(height: compact ? 36 : 96)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PJ.line, lineWidth: 1)
        )
        .onAppear { thumbs.load(item) }
    }
}

private func fileSymbol(_ name: String) -> String {
    let ext = (name as NSString).pathExtension.lowercased()
    if ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"].contains(ext) {
        return "photo"
    }
    if ["mp4", "mov", "m4v"].contains(ext) { return "film" }
    if ["mp3", "wav", "aiff", "m4a"].contains(ext) { return "waveform" }
    if ext == "pdf" { return "doc.richtext" }
    return "doc.fill"
}

private struct OnboardingFlow: View {
    @ObservedObject var store: DriveStore
    private let titles = [
        "Quick file state for agents.",
        "Bring the whole library. Leave the disk alone.",
        "Keep \(Brand.name) running.",
        "Let \(Brand.name) see drops.",
        "Mount it in Finder.",
    ]
    private let bodies = [
        "\(Brand.name) shows up in the Finder sidebar. Files stay in the cloud; this Mac only reads the bytes an app needs.",
        "Connect Backblaze, S3, or a local disk. Keys stay on this Mac. Individual includes \(ByteFormat.precise(Brand.includedBytes)).",
        "Background activity is how it stays available without a Dock icon. macOS will list \(Brand.name) under App Background Activity.",
        "Accessibility is how a drop onto the drive gets noticed, so Finder refreshes and the file is there.",
        "Mount puts \(Brand.name) next to My Drive in the Finder sidebar.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                Group {
                    if store.step == 0 {
                        FinderScene().frame(height: 220)
                    } else {
                        Mark(size: 78)
                    }
                }
                .id("hero-\(store.step)")
                .transition(.opacity.combined(with: .offset(y: 14)))

                Text(titles[store.step])
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(PJ.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 640)

                Text(bodies[store.step])
                    .font(.system(size: 15))
                    .foregroundStyle(PJ.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)

                if store.step == 1 {
                    Text("\(store.bucket)  ·  \(store.region)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PJ.ink)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(PJ.surface, in: Capsule())
                        .overlay(Capsule().stroke(PJ.hairline, lineWidth: 1))
                }
                if store.step == 4 {
                    Text(store.status).font(.system(size: 13)).foregroundStyle(PJ.secondary)
                }
            }
            .animation(PJ.ease, value: store.step)
            Spacer(minLength: 8)
            HStack {
                HStack(spacing: 10) {
                    Text("\(store.step + 1) of \(titles.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PJ.tertiary)
                        .monospacedDigit()
                    Capsule().fill(PJ.track).frame(width: 72, height: 3)
                        .overlay(alignment: .leading) {
                            Capsule().fill(PJ.ink).frame(width: 72 * CGFloat(store.step + 1) / CGFloat(titles.count))
                        }
                }
                Spacer()
                if store.step > 0 {
                    Button("Back") { withAnimation(PJ.ease) { store.step -= 1 } }.buttonStyle(QuietButton())
                }
                Button(store.step == titles.count - 1 ? "Finish" : "Continue") { advance() }
                    .buttonStyle(InkButton())
            }
            .frame(height: 82)
        }
        .padding(.horizontal, 28)
        .background(PJ.canvas)
    }

    private func advance() {
        switch store.step {
        case 2:
            store.enableBackground()
            store.openExtensionSettings()
        case 3:
            store.openAccessibilitySettings()
        case 4:
            store.mount()
            withAnimation(PJ.ease) { store.finishOnboarding() }
            return
        default:
            break
        }
        withAnimation(PJ.ease) { store.step = min(store.step + 1, titles.count - 1) }
    }
}

private struct FinderScene: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 1, green: 0.76, blue: 0.18)).frame(width: 10, height: 10)
                    Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 10, height: 10)
                }
                .padding(.bottom, 8)
                label("Recents")
                label("Documents")
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill").font(.system(size: 11))
                    Text(Brand.name).font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(PJ.ink)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(PJ.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                label("Macintosh HD")
                Spacer()
            }
            .padding(12)
            .frame(width: 168)
            .background(PJ.wash)
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(PJ.blue)
                    Text("Drop files here").font(.system(size: 14, weight: .semibold)).foregroundStyle(PJ.ink)
                    Text("They upload to Backblaze.").font(.system(size: 11)).foregroundStyle(PJ.secondary)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 36)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4])).foregroundStyle(PJ.line))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(PJ.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PJ.hairline, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.10), radius: 24, y: 14)
        .frame(maxWidth: 560)
    }

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 12)).foregroundStyle(PJ.secondary).padding(.horizontal, 8).frame(height: 22, alignment: .leading)
    }
}
