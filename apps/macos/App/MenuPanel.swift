import SwiftUI

struct MenuPanel: View {
    @EnvironmentObject private var store: DriveStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            openButton
            section("DRIVES")
            driveCard
            section("NETWORK")
            networkCard
            footer
        }
        .padding(12)
        .frame(width: 360)
        .background(PJ.wash)
        .photojellyTheme(store.theme)
        .onAppear { store.boot() }
        .onReceive(NotificationCenter.default.publisher(for: .photojellyOpenHome)) { _ in
            openHome()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Mark(size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("My \(Brand.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PJ.ink)
                Text(store.accountEmail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(PJ.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(store.mounted ? Color(red: 0.18, green: 0.62, blue: 0.34) : PJ.tertiary)
                    .frame(width: 6, height: 6)
                Text(store.updateStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PJ.ink)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(PJ.surface, in: Capsule())
            .overlay(Capsule().stroke(PJ.line, lineWidth: 1))
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var openButton: some View {
        Button {
            openHome()
        } label: {
            Text("Open \(Brand.name)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PJ.onFilled)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(PJ.filled, in: Capsule())
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.bottom, 16)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(PJ.tertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
    }

    private var driveCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PJ.ink)
                Text(store.mounted ? Brand.mountPath : "Not mounted")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PJ.secondary)
            }
            Spacer()
            iconButton("arrow.up.forward") { store.reveal() }
                .disabled(!store.mounted)
                .opacity(store.mounted ? 1 : 0.35)
            iconButton("eject") {
                store.mounted ? store.eject() : store.mount()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(PJ.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PJ.line, lineWidth: 1))
        .padding(.bottom, 16)
    }

    private var networkCard: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PJ.secondary)
                Text(ByteFormat.rate(store.downloadRate))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(PJ.ink)
                Text(ByteFormat.session(store.session.downloaded))
                    .font(.system(size: 11))
                    .foregroundStyle(PJ.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(PJ.line)
                .frame(width: 1, height: 54)
                .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("Upload")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PJ.secondary)
                Text(ByteFormat.rate(store.uploadRate))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(PJ.ink)
                Text(ByteFormat.session(store.session.uploaded))
                    .font(.system(size: 11))
                    .foregroundStyle(PJ.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(PJ.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PJ.line, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            footerRow("sparkle", "Set Up \(Brand.name)") {
                store.reopenSetup()
                openHome()
            }
            footerRow("arrow.triangle.2.circlepath", "Check for Updates") {
                store.checkForUpdates()
            }
            footerRow("waveform.path.ecg", "Open Debug Dashboard") {
                store.settingsTab = .advanced
                store.showSettings = true
                openHome()
            }
            footerRow("gearshape", "Settings") {
                store.settingsTab = .general
                store.showSettings = true
                openHome()
            }
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .frame(width: 16)
                    Text("Quit \(Brand.name)")
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 12))
                        .foregroundStyle(PJ.tertiary)
                }
                .font(.system(size: 13.5))
                .foregroundStyle(PJ.ink)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private func footerRow(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(PJ.secondary)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(PJ.ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PJ.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openHome() {
        if let existing = NSApp.windows.first(where: { $0.frame.width > 600 }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "home")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct Mark: View {
    var size: CGFloat = 28
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(PJ.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(PJ.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.38, weight: .medium))
                    .foregroundStyle(PJ.ink)
            }
            .frame(width: size, height: size)
    }
}
