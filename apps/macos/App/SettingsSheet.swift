import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct SettingsSheet: View {
    @ObservedObject var store: DriveStore

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(PJ.line).frame(width: 1)
            pane
        }
        .background(PJ.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PJ.line, lineWidth: 1)
        )
        .photojellyTheme(store.theme)
        .onAppear {
            store.cache.refresh(prefs: store.prefs)
            if store.settingsTab == .storage {
                Task { await store.loadAllUsage() }
            }
        }
        .onChange(of: store.settingsTab) { _, tab in
            if tab == .storage {
                Task { await store.loadAllUsage() }
            }
        }
        .onExitCommand {
            if store.connectKind != nil {
                store.connectKind = nil
            } else {
                store.showSettings = false
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PJ.ink)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 12)
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { store.settingsTab = tab }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(tab))
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 16)
                        Text(tab.title)
                            .font(.system(size: 13, weight: store.settingsTab == tab ? .semibold : .medium))
                        Spacer()
                    }
                    .foregroundStyle(store.settingsTab == tab ? PJ.ink : PJ.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        store.settingsTab == tab ? PJ.fill : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 188)
        .background(PJ.canvas)
    }

    private var pane: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                Group {
                    switch store.settingsTab {
                    case .general: general
                    case .people: people
                    case .storage: storage
                    case .billing: billing
                    case .advanced: advanced
                    }
                }
                .padding(.horizontal, 36)
                .padding(.top, 28)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { store.showSettings = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PJ.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Account") {
                SettingsRow("Email") {
                    Text(store.prefs.email.isEmpty ? "Not signed in" : store.prefs.email)
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                }
                hairline
                SettingsRow("Session", subtitle: "Signed in on this Mac. Signing out ejects all drives.") {
                    QuietCapsule(title: "Sign out") { store.eject() }
                }
            }
            hairline.padding(.vertical, 18)
            section("Workspace") {
                SettingsRow("Workspace name") {
                    TextField("My Space", text: $store.prefs.workspaceName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 12)
                        .frame(width: 200, height: 32)
                        .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
                        .onChange(of: store.prefs.workspaceName) { _, _ in store.savePrefs() }
                }
                .padding(.top, 6)
                SettingsRow("Workspace image") {
                    ZStack {
                        Circle().fill(PJ.ink)
                        Text(String(store.prefs.workspaceName.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(PJ.onFilled)
                    }
                    .frame(width: 32, height: 32)
                }
                .padding(.vertical, 10)
                SettingsRow("About", subtitle: "What lives in this workspace?") {
                    TextEditor(text: $store.prefs.about)
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                        .scrollContentBackground(.hidden)
                        .frame(width: 260, height: 72)
                        .padding(8)
                        .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
                        .onChange(of: store.prefs.about) { _, _ in store.savePrefs() }
                }
            }
            hairline.padding(.vertical, 18)
            section("Appearance") {
                SettingsRow("Theme", subtitle: "Match your system appearance, or pick one and stay there") {
                    Segmented(items: Array(AppTheme.allCases), title: \.title, selection: Binding(
                        get: { store.theme },
                        set: { store.theme = $0 }
                    ))
                }
            }
            hairline.padding(.vertical, 18)
            section("Updates") {
                SettingsRow(Brand.name) {
                    HStack(spacing: 10) {
                        Text(store.updateStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(PJ.secondary)
                        QuietCapsule(title: "Check", action: store.checkForUpdates)
                    }
                }
            }
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Team members")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                    Text("People who can see this workspace’s drive.")
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.secondary)
                }
                Spacer()
                QuietCapsule(title: "Invite", filled: true, action: store.beginInvite)
            }
            if store.prefs.members.isEmpty {
                emptyCard("No teammates yet", "Invite someone to share this drive.")
            } else {
                VStack(spacing: 0) {
                    ForEach(store.prefs.members) { member in
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(PJ.fill)
                                Text(String(member.email.prefix(1)).uppercased())
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(PJ.ink)
                            }
                            .frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.email).font(.system(size: 13, weight: .medium)).foregroundStyle(PJ.ink)
                                Text(member.role.capitalized).font(.system(size: 12)).foregroundStyle(PJ.secondary)
                            }
                            Spacer()
                            Menu {
                                ForEach(TeamRole.allCases) { role in
                                    Button(role.title) { store.setMemberRole(member, role: role) }
                                }
                            } label: {
                                Text(member.teamRole.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PJ.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            Button("Remove") {
                                store.removeMember(member)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PJ.secondary)
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 10)
                        hairline
                    }
                }
            }
        }
    }

    private static let connectKinds: [StorageKind] = [
        .backblaze, .s3, .r2, .wasabi, .minio, .smb
    ]

    private var storage: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PJ.ink)
                Text("Connect Backblaze, S3, or a local disk. Individual includes \(ByteFormat.precise(Brand.includedBytes)); extra is $6 / month per 500 GB. Keys stay on this Mac.")
                    .font(.system(size: 13))
                    .foregroundStyle(PJ.secondary)
            }

            usageCard
            driveList
        }
    }

    private var usageCard: some View {
        let slices = storageSlices
        let used = slices.reduce(UInt64(0)) { $0 + $1.bytes }
        let files = slices.reduce(0) { $0 + $1.files }
        let capacity = accessCapacity(slices)
        let cloudPlan = slices.contains { $0.kind.isObjectStore }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ByteFormat.precise(used))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(PJ.ink)
                        Text("used")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PJ.secondary)
                    }
                    Text(accessCaption(used: used, slices: slices))
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(files.formatted()) files")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PJ.ink)
                    Button {
                        Task { await store.loadAllUsage() }
                    } label: {
                        HStack(spacing: 4) {
                            if store.loadingUsage { ProgressView().controlSize(.mini) }
                            Text(store.loadingUsage ? "Measuring…" : "Refresh")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PJ.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            StorageBar(slices: slices, used: used, capacity: capacity)
            if let capacity, capacity > 0 {
                HStack {
                    Text(ByteFormat.precise(used))
                    Spacer()
                    Text(ByteFormat.precise(capacity) + (cloudPlan ? " included" : ""))
                }
                .font(.system(size: 11))
                .foregroundStyle(PJ.tertiary)
            }
            if store.loadingUsage && slices.isEmpty {
                Text("Measuring connected drives…")
                    .font(.system(size: 12))
                    .foregroundStyle(PJ.secondary)
            }
        }
        .padding(16)
        .background(PJ.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var driveList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect a drive")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PJ.tertiary)
            VStack(spacing: 0) {
                ForEach(Array(Self.connectKinds.enumerated()), id: \.element) { index, kind in
                    if index > 0 { hairline.padding(.leading, 50) }
                    providerSection(kind)
                }
                hairline.padding(.leading, 50)
                localSection(.folder)
                hairline.padding(.leading, 50)
                localSection(.disk)
            }
            .background(PJ.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PJ.line, lineWidth: 1)
            )
        }
    }

    private var usageSubtitle: String {
        let drives = store.vault.accounts.count + standaloneLocations.count
        let cloud = store.vault.accounts.filter(\.storageKind.isObjectStore).count
        let local = store.vault.accounts.filter { !$0.storageKind.isObjectStore }.count + standaloneLocations.count
        let driveWord = drives == 1 ? "drive" : "drives"
        return "across \(drives) \(driveWord) · \(cloud) cloud · \(local) local"
    }

    private func accessCapacity(_ slices: [StorageSlice]) -> UInt64? {
        if slices.contains(where: { $0.kind.isObjectStore }) {
            return Brand.includedBytes
        }
        let caps = slices.compactMap(\.capacity)
        if caps.isEmpty { return slices.isEmpty ? nil : Brand.includedBytes }
        return caps.reduce(UInt64(0), +)
    }

    private func accessCaption(used: UInt64, slices: [StorageSlice]) -> String {
        if slices.isEmpty { return "Connect a drive to see used and available space." }
        let localCaps = slices.filter { !$0.kind.isObjectStore }.compactMap(\.capacity)
        let localTotal = localCaps.reduce(UInt64(0), +)
        let cloud = slices.contains { $0.kind.isObjectStore }
        if cloud {
            return "of \(ByteFormat.precise(Brand.includedBytes)) included · extra $6 / 500 GB · \(usageSubtitle)"
        }
        if localTotal > 0 {
            let left = localTotal > used ? localTotal - used : 0
            return "of \(ByteFormat.precise(localTotal)) available · \(ByteFormat.precise(left)) free · \(usageSubtitle)"
        }
        return "of \(ByteFormat.precise(Brand.includedBytes)) included · \(usageSubtitle)"
    }

    private var standaloneLocations: [LocationRecord] {
        store.prefs.locations.filter { location in
            guard let accountId = location.accountId else { return true }
            return !store.vault.accounts.contains(where: { $0.id == accountId })
        }
    }

    private var storageSlices: [StorageSlice] {
        var rows: [StorageSlice] = []
        for account in store.vault.accounts {
            rows.append(StorageSlice(
                id: account.id.uuidString,
                title: accountDisplayName(account),
                detail: accountSubtitle(account),
                bytes: accountBytes(account),
                files: store.accountUsage[account.id]?.files ?? 0,
                kind: account.storageKind,
                capacity: accountCapacity(account)
            ))
        }
        for location in standaloneLocations {
            rows.append(StorageSlice(
                id: location.id.uuidString,
                title: location.name,
                detail: location.path,
                bytes: store.locationUsage[location.id] ?? 0,
                files: 0,
                kind: location.storageKind,
                capacity: store.locationCapacity[location.id]
            ))
        }
        return rows
    }

    private func accounts(for kind: StorageKind) -> [StorageAccount] {
        store.vault.accounts.filter { $0.storageKind == kind }
    }

    private func locations(for kind: StorageKind) -> [LocationRecord] {
        standaloneLocations.filter { $0.storageKind == kind }
    }

    private func providerSection(_ kind: StorageKind) -> some View {
        let accounts = accounts(for: kind)
        let bytes = accounts.reduce(UInt64(0)) { $0 + accountBytes($1) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderMark(kind: kind, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                    Text(accounts.isEmpty ? "Not connected" : providerLine(count: accounts.count, bytes: bytes, capacity: accounts.compactMap(accountCapacity).max(), noun: "account"))
                        .font(.system(size: 11))
                        .foregroundStyle(PJ.secondary)
                }
                Spacer(minLength: 12)
                if accounts.isEmpty {
                    rowAction("Connect", filled: true) { store.beginConnect(kind) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(accounts) { account in
                        nestedAccountRow(account)
                    }
                    addAnotherRow { store.beginConnect(kind) }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func localSection(_ kind: StorageKind) -> some View {
        let items = locations(for: kind)
        let bytes = items.reduce(UInt64(0)) { $0 + (store.locationUsage[$1.id] ?? 0) }
        let capacity = items.compactMap { store.locationCapacity[$0.id] }.max()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ProviderMark(kind: kind, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                    Text(items.isEmpty ? "Not connected" : providerLine(count: items.count, bytes: bytes, capacity: capacity, noun: "location"))
                        .font(.system(size: 11))
                        .foregroundStyle(PJ.secondary)
                }
                Spacer(minLength: 12)
                if items.isEmpty {
                    rowAction("Connect", filled: true) {
                        if kind == .disk { store.connectDisk() } else { store.connectFolder() }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { location in
                        nestedLocationRow(location)
                    }
                    addAnotherRow {
                        if kind == .disk { store.connectDisk() } else { store.connectFolder() }
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func nestedAccountRow(_ account: StorageAccount) -> some View {
        let bytes = accountBytes(account)
        return HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(account.storageKind.swatch.opacity(0.55))
                .frame(width: 2, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(accountDisplayName(account))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PJ.ink)
                Text(usedOfLine(bytes: bytes, capacity: accountCapacity(account), detail: accountSubtitle(account)))
                    .font(.system(size: 11))
                    .foregroundStyle(PJ.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if store.vault.primaryId == account.id {
                statusChip("My Drive")
            } else if account.storageKind.isObjectStore {
                rowAction("Use as My Drive") { store.makePrimary(account) }
            }
            rowAction("Remove") { store.removeAccount(account) }
        }
        .padding(.leading, 40)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
    }

    private func nestedLocationRow(_ location: LocationRecord) -> some View {
        let bytes = store.locationUsage[location.id] ?? 0
        let capacity = store.locationCapacity[location.id]
        return HStack(alignment: .center, spacing: 10) {
            Capsule()
                .fill(location.storageKind.swatch.opacity(0.55))
                .frame(width: 2, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PJ.ink)
                Text(usedOfLine(bytes: bytes, capacity: capacity, detail: location.path))
                    .font(.system(size: 11))
                    .foregroundStyle(PJ.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            rowAction("Disconnect") { store.disconnectLocation(location) }
        }
        .padding(.leading, 40)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
    }

    private func addAnotherRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text("Add another")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(PJ.ink)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(PJ.surface, in: Capsule())
            .overlay(Capsule().stroke(PJ.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.leading, 40)
        .padding(.trailing, 14)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowAction(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(filled ? PJ.onFilled : PJ.ink)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(filled ? PJ.filled : PJ.surface, in: Capsule())
                .overlay(Capsule().stroke(filled ? Color.clear : PJ.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PJ.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(PJ.fill, in: Capsule())
    }

    private func providerLine(count: Int, bytes: UInt64, capacity: UInt64?, noun: String) -> String {
        let item = count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        return item + " · " + usedOfLine(bytes: bytes, capacity: capacity, detail: "")
    }

    private func usedOfLine(bytes: UInt64, capacity: UInt64?, detail: String) -> String {
        var parts: [String] = []
        if let capacity, capacity > 0 {
            parts.append("\(ByteFormat.precise(bytes)) of \(ByteFormat.precise(capacity))")
        } else if bytes > 0 {
            parts.append("\(ByteFormat.precise(bytes)) used")
        }
        if !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? "No size yet" : parts.joined(separator: " · ")
    }

    private func accountCapacity(_ account: StorageAccount) -> UInt64? {
        if account.storageKind.isObjectStore {
            return store.accountUsage[account.id]?.capacity ?? Brand.includedBytes
        }
        if let location = store.prefs.locations.first(where: { $0.accountId == account.id }) {
            return store.locationCapacity[location.id]
        }
        return nil
    }

    private func accountBytes(_ account: StorageAccount) -> UInt64 {
        if let usage = store.accountUsage[account.id] { return usage.bytes }
        if let location = store.prefs.locations.first(where: { $0.accountId == account.id }) {
            return store.locationUsage[location.id] ?? 0
        }
        return 0
    }

    private func isGenericAccountName(_ account: StorageAccount) -> Bool {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return true }
        if name == account.storageKind.title { return true }
        let prefix = account.storageKind.title + " "
        guard name.hasPrefix(prefix) else { return false }
        return name.dropFirst(prefix.count).allSatisfy(\.isNumber)
    }

    private func accountDisplayName(_ account: StorageAccount) -> String {
        if !isGenericAccountName(account) { return account.name }
        if account.storageKind.isObjectStore, !account.bucket.isEmpty { return account.bucket }
        if !account.smbShare.isEmpty {
            return account.smbHost.isEmpty ? account.smbShare : "\(account.smbHost)/\(account.smbShare)"
        }
        return account.storageKind.title
    }

    private func accountSubtitle(_ account: StorageAccount) -> String {
        if account.storageKind.isObjectStore {
            let host = account.endpoint
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            if isGenericAccountName(account) { return host }
            return account.bucket.isEmpty ? host : "\(account.bucket) · \(host)"
        }
        let user = account.smbUser.isEmpty ? "guest" : account.smbUser
        return "\(user)@\(account.smbHost)/\(account.smbShare)"
    }

    private var billing: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Plan & Billing").font(.system(size: 20, weight: .semibold)).foregroundStyle(PJ.ink)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Brand.trialDays) days left in your free trial")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(PJ.ink)
                    Text("Individual · $\(Int(Brand.individualDollars))/month · \(ByteFormat.precise(Brand.includedBytes)) included")
                        .font(.system(size: 13)).foregroundStyle(PJ.secondary)
                }
                Spacer()
                QuietCapsule(title: "Subscribe", filled: true) { store.subscribe() }
            }
            .padding(18)
            .background(PJ.trialFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            SettingsRow("Extra storage") {
                Text("$6 / month per 500 GB after \(ByteFormat.precise(Brand.includedBytes))")
                    .font(.system(size: 13)).foregroundStyle(PJ.ink)
            }
            if let usage = store.usage, usage.bytes > Brand.includedBytes {
                SettingsRow("Estimated extra this month") {
                    Text(ByteFormat.dollars(usage.extraMonthlyDollars)).font(.system(size: 13)).foregroundStyle(PJ.ink)
                }
            }
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Jev labels") {
                SettingsRow(
                    "OpenRouter",
                    subtitle: DriveSecrets.resolvedKey().isEmpty
                        ? "Paste an OpenRouter key. Jev (~typesafe/jev-latest) labels every file. The key stays on this Mac."
                        : "Key saved. Jev labels files in the current folder as they appear."
                ) {
                    HStack(spacing: 8) {
                        SecureField("sk-or-v1-…", text: $store.openRouterKeyDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(PJ.ink)
                            .padding(.horizontal, 12)
                            .frame(width: 200, height: 32)
                            .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
                        QuietCapsule(title: "Save", filled: true, action: store.saveOpenRouterKey)
                    }
                }
                .padding(.bottom, 16)
                SettingsRow(
                    store.labeling ? "Labeling…" : "Library labels",
                    subtitle: store.labelStatus.isEmpty
                        ? "Search uses Jev labels. Next: duplicates, albums, and keep vs junk."
                        : store.labelStatus
                ) {
                    QuietCapsule(title: store.labeling ? "Working…" : "Label this folder") {
                        Task { await store.labelCurrentFolder() }
                    }
                    .disabled(store.labeling || DriveSecrets.resolvedKey().isEmpty)
                }
            }
            hairline.padding(.vertical, 22)
            section("Cache") {
                SettingsRow(
                    "\(ByteFormat.precise(store.cache.diskBytes)) on disk",
                    subtitle: "\(Brand.name) keeps recently used blocks on disk so files open instantly · \(store.cache.blockCount) blocks · previews \(ByteFormat.precise(store.cache.previewBytes)) (independent 512 MiB cap)"
                ) {
                    HStack(spacing: 8) {
                        IconCircle(symbol: "arrow.clockwise") {
                            store.cache.refresh(prefs: store.prefs)
                        }
                        QuietCapsule(title: "Clear cache") {
                            store.cache.clearUnpinned(prefs: store.prefs)
                            store.savePrefs()
                        }
                    }
                }
                .padding(.bottom, 16)
                SettingsRow("In memory", subtitle: "Hot blocks kept in RAM for instant reads") {
                    Text("\(ByteFormat.precise(store.cache.memoryBytes)) of \(ByteFormat.precise(store.cache.memoryCap))")
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                }
                .padding(.bottom, 16)
                SettingsRow("Cache location", subtitle: store.cache.directory(prefs: store.prefs).path) {
                    QuietCapsule(title: "Change…", action: pickCache)
                }
                .padding(.bottom, 14)
                HStack(spacing: 14) {
                    Text("Cache limit")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                        .frame(width: 88, alignment: .leading)
                    QuietSlider(
                        value: $store.prefs.cacheLimitGB,
                        range: 1...200,
                        onEnded: { store.savePrefs() }
                    )
                    Text("\(Int(store.prefs.cacheLimitGB)) GiB")
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                        .frame(width: 52, alignment: .trailing)
                }
            }
            hairline.padding(.vertical, 22)
            section("Uploads") {
                SettingsRow("Compression", subtitle: store.compression.detail) {
                    Segmented(
                        items: Array(UploadCompression.allCases),
                        title: \.title,
                        selection: Binding(
                            get: { store.compression },
                            set: { store.compression = $0 }
                        )
                    )
                }
                .padding(.bottom, 16)
                SettingsRow("Upload bandwidth", subtitle: "\(Brand.name) adjusts upload speed to your connection automatically.") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(store.prefs.uploadKbps == 0 ? "Default" : "\(store.prefs.uploadKbps)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PJ.ink)
                        Text("Adaptive")
                            .font(.system(size: 11))
                            .foregroundStyle(PJ.secondary)
                    }
                }
                .padding(.bottom, 10)
                BandwidthSlider(kbps: $store.prefs.uploadKbps, onEnded: { store.savePrefs() })
                    .padding(.trailing, 4)
            }
            hairline.padding(.vertical, 22)
            section("Offline access") {
                SettingsRow(
                    store.prefs.pins.isEmpty ? "No pinned items" : "\(store.prefs.pins.count) pinned items",
                    subtitle: "Files with offline access are kept fully downloaded on this device"
                ) {
                    QuietCapsule(title: "Manage") {
                        store.sidebar = .drive
                        store.showSettings = false
                    }
                }
                ForEach(store.prefs.pins) { pin in
                    HStack(spacing: 10) {
                        Image(systemName: pin.isFolder ? "folder.fill" : "doc")
                            .foregroundStyle(PJ.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pin.name).font(.system(size: 13, weight: .medium)).foregroundStyle(PJ.ink)
                            Text("\(ByteFormat.precise(pin.bytes)) · kept on this Mac")
                                .font(.system(size: 11)).foregroundStyle(PJ.secondary)
                        }
                        Spacer()
                        Button("Unpin") { store.unpin(pin.key) }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PJ.secondary)
                            .buttonStyle(.plain)
                    }
                    .padding(.top, 10)
                }
            }
            hairline.padding(.vertical, 22)
            section("Mount") {
                SettingsRow("Mount method", subtitle: store.mountMethod.detail) {
                    Segmented(items: Array(MountMethod.allCases), title: \.title, selection: Binding(
                        get: { store.mountMethod },
                        set: { store.applyMountMethod($0) }
                    ))
                }
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(PJ.line).frame(height: 1)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PJ.tertiary)
            content()
        }
    }

    private func emptyCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(PJ.ink)
            Text(body).font(.system(size: 13)).foregroundStyle(PJ.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PJ.wash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func pickCache() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use this folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            store.prefs.cacheDirectory = url.path
            store.savePrefs()
        }
    }

    private func icon(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return "gearshape"
        case .people: return "person.2"
        case .storage: return "internaldrive"
        case .billing: return "creditcard"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

struct InviteMemberSheet: View {
    @ObservedObject var store: DriveStore
    @State private var email = ""
    @State private var role: TeamRole = .editor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                    Text("They’ll be able to see this workspace’s drive. Sharing still needs a \(Brand.name) account.")
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    store.showInvite = false
                    store.inviteError = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PJ.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Email")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PJ.tertiary)
                    TextField("name@company.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
                        .onSubmit { _ = store.submitInvite(email: email, role: role) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Role")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PJ.tertiary)
                    Segmented(
                        items: Array(TeamRole.allCases),
                        title: \.title,
                        selection: $role
                    )
                }
            }

            if !store.inviteError.isEmpty {
                Text(store.inviteError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                Spacer()
                QuietCapsule(title: "Cancel") {
                    store.showInvite = false
                    store.inviteError = ""
                }
                QuietCapsule(title: "Invite", filled: true) {
                    _ = store.submitInvite(email: email, role: role)
                }
                .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: 440)
        .background(PJ.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PJ.line, lineWidth: 1))
        .onAppear { store.inviteError = "" }
    }
}

struct ConnectStorageSheet: View {
    @ObservedObject var store: DriveStore
    var kind: StorageKind
    @State private var name = ""
    @State private var endpoint = ""
    @State private var region = ""
    @State private var bucket = ""
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var r2Account = ""
    @State private var smbHost = ""
    @State private var smbShare = ""
    @State private var smbUser = ""
    @State private var smbPassword = ""
    @State private var asPrimary = true
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ProviderMark(kind: kind, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect drive")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PJ.ink)
                    Text(kind.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PJ.ink)
                    Text(kind.setupHint)
                        .font(.system(size: 13))
                        .foregroundStyle(PJ.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("You can connect more than one \(kind.title) account.")
                        .font(.system(size: 12))
                        .foregroundStyle(PJ.tertiary)
                }
                Spacer(minLength: 8)
                Button {
                    store.connectKind = nil
                    store.storageError = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PJ.tertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Name on this Mac", text: $name, placeholder: kind.title)
                    if kind.isObjectStore {
                        if kind == .r2 {
                            field("R2 account ID", text: $r2Account, placeholder: "abc123")
                        }
                        if !kind.regionChoices.isEmpty {
                            regionPicker
                        } else {
                            field("Region", text: $region, placeholder: kind.defaultRegion)
                        }
                        field("Endpoint", text: $endpoint, placeholder: kind.defaultEndpoint)
                        field("Bucket", text: $bucket, placeholder: "my-photos")
                        field(kind.keyIdLabel, text: $accessKeyId, placeholder: kind == .backblaze ? "0004…" : "AKIA…")
                        field(kind.secretLabel, text: $secretAccessKey, placeholder: "paste secret", secure: true)
                        Toggle("Use as My Drive", isOn: $asPrimary)
                            .toggleStyle(.checkbox)
                            .foregroundStyle(PJ.ink)
                            .padding(.top, 4)
                    } else {
                        field("Host", text: $smbHost, placeholder: "192.168.1.10 or nas.local")
                        field("Share", text: $smbShare, placeholder: "photos")
                        field("User", text: $smbUser, placeholder: "guest")
                        field("Password", text: $smbPassword, placeholder: "optional", secure: true)
                    }
                }
            }
            .frame(maxHeight: 340)

            if !store.storageError.isEmpty {
                Text(store.storageError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                if let url = kind.docsURL {
                    Button("Where do I get keys?") {
                        NSWorkspace.shared.open(url)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PJ.secondary)
                    .buttonStyle(.plain)
                }
                Spacer()
                QuietCapsule(title: "Cancel") {
                    store.connectKind = nil
                    store.storageError = ""
                }
                QuietCapsule(title: testing ? "Checking…" : "Connect", filled: true, action: save)
                    .disabled(testing || !canSave)
            }
            .padding(.top, 16)
        }
        .padding(28)
        .frame(width: 520)
        .background(PJ.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PJ.line, lineWidth: 1))
        .onAppear {
            name = store.uniqueAccountName(kind.title)
            endpoint = kind.defaultEndpoint
            region = kind.defaultRegion
            asPrimary = store.vault.primaryId == nil
            store.storageError = ""
        }
        .onChange(of: region) { _, code in
            if !kind.regionChoices.isEmpty {
                endpoint = kind.endpoint(region: code, accountId: r2Account)
            }
        }
        .onChange(of: r2Account) { _, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                endpoint = "https://\(trimmed).r2.cloudflarestorage.com"
            }
        }
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Region")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PJ.tertiary)
            Picker("Region", selection: $region) {
                ForEach(kind.regionChoices) { choice in
                    Text(choice.title).tag(choice.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
        }
    }

    private var canSave: Bool {
        if kind.isObjectStore {
            return !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !smbHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !smbShare.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(PJ.tertiary)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(PJ.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(PJ.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(PJ.line))
        }
    }

    private func save() {
        testing = true
        store.storageError = ""
        let account = StorageAccount(
            kind: kind,
            name: name.isEmpty ? kind.title : name,
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            bucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
            accessKeyId: accessKeyId.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines),
            smbHost: smbHost.trimmingCharacters(in: .whitespacesAndNewlines),
            smbShare: smbShare.trimmingCharacters(in: .whitespacesAndNewlines),
            smbUser: smbUser.trimmingCharacters(in: .whitespacesAndNewlines),
            smbPassword: smbPassword
        )
        store.saveStorageAccount(account, asPrimary: asPrimary)
        testing = false
    }
}

struct StorageSlice: Identifiable {
    var id: String
    var title: String
    var detail: String
    var bytes: UInt64
    var files: Int
    var kind: StorageKind
    var capacity: UInt64? = nil
    var color: Color { kind.swatch }
}

struct StorageBar: View {
    var slices: [StorageSlice]
    var used: UInt64
    var capacity: UInt64?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let denom: Double = {
                if let capacity, capacity > 0 { return Double(capacity) }
                return Double(max(used, 1)) * 6
            }()
            ZStack(alignment: .leading) {
                Capsule().fill(PJ.track)
                if used > 0 {
                    HStack(spacing: 1) {
                        ForEach(slices.filter { $0.bytes > 0 }) { slice in
                            Capsule()
                                .fill(slice.color)
                                .frame(width: max(4, min(width, width * CGFloat(Double(slice.bytes) / denom))))
                        }
                    }
                }
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }
}

struct ProviderMark: View {
    var kind: StorageKind
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(kind.swatch.opacity(0.14))
            if let url = kind.faviconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(size * 0.18)
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Group {
            if kind.faviconHost != nil {
                Text(kind.initial)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(kind.swatch)
            } else {
                Image(systemName: kind.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(kind.swatch)
            }
        }
    }
}
