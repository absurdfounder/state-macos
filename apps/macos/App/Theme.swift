import SwiftUI
import AppKit

enum PJ {
    static let ink = Color.adaptive(light: 0x0A0A0A, dark: 0xF4F4F5)
    static let secondary = Color.adaptive(light: 0x6B6B70, dark: 0xA1A1AA)
    static let tertiary = Color.adaptive(light: 0x9E9EA3, dark: 0x6E6E73)
    static let blue = Color.adaptive(light: 0x0A7CFF, dark: 0x4C9FFF)
    static let wash = Color.adaptive(light: 0xF7F7F9, dark: 0x1C1C1F)
    static let fill = Color.adaptive(light: 0xF4F4F6, dark: 0x2C2C31)
    static let line = Color.adaptiveStroke(light: 0.08, dark: 0.12)
    static let hairline = Color.adaptiveStroke(light: 0.08, dark: 0.12)
    static let canvas = Color.adaptive(light: 0xFFFFFF, dark: 0x111113)
    static let surface = Color.adaptive(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let elevated = Color.adaptive(light: 0xFFFFFF, dark: 0x2A2A2E)
    static let muted = Color.adaptive(light: 0xF7F7F8, dark: 0x242428)
    static let drop = Color.adaptive(light: 0xF4F8FF, dark: 0x152033)
    static let filled = Color.adaptive(light: 0x141414, dark: 0xF2F2F2)
    static let onFilled = Color.adaptive(light: 0xFFFFFF, dark: 0x111111)
    static let track = Color.adaptive(light: 0xE5E7EB, dark: 0x3A3A40)
    static let dim = Color.adaptive(lightAlpha: 0.16, darkAlpha: 0.52)
    static let trialFill = Color.adaptive(light: 0xFFF7ED, dark: 0x3A2A18)
    static let trialInk = Color.adaptive(light: 0xC2410C, dark: 0xFDBA74)
    static let trialBody = Color.adaptive(light: 0x9A3412, dark: 0xFCD9B6)
    static let folderTop = Color.adaptive(light: 0xE4E4E9, dark: 0x5A5A64)
    static let folderBot = Color.adaptive(light: 0xC4C4CC, dark: 0x3A3A42)
    static let ease = Animation.timingCurve(0.22, 0.68, 0.35, 1, duration: 0.42)
}

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func applyToApp() {
        switch self {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static func adaptive(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(nsColor: dynamicNSColor(light: light, dark: dark, alpha: alpha))
    }

    static func adaptiveStroke(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? 1 : 0, alpha: isDark ? dark : light)
        }))
    }

    static func adaptive(lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: 0, alpha: isDark ? darkAlpha : lightAlpha)
        }))
    }
}

private func dynamicNSColor(light: UInt32, dark: UInt32, alpha: Double) -> NSColor {
    NSColor(name: nil, dynamicProvider: { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        let color = NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
        return color
    })
}

extension View {
    func photojellyTheme(_ theme: AppTheme) -> some View {
        preferredColorScheme(theme.colorScheme)
    }
}

struct QuietCapsule: View {
    var title: String
    var icon: String? = nil
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(filled ? PJ.onFilled : PJ.ink)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(filled ? PJ.filled : PJ.surface, in: Capsule())
            .overlay(Capsule().stroke(filled ? Color.clear : PJ.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerHover()
    }
}

struct IconCircle: View {
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PJ.secondary)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(PJ.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointerHover()
    }
}

struct Segmented<Item: Identifiable & Hashable>: View {
    var items: [Item]
    var title: KeyPath<Item, String>
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    Text(item[keyPath: title])
                        .font(.system(size: 12, weight: selection == item ? .semibold : .regular))
                        .foregroundStyle(selection == item ? PJ.ink : PJ.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(selection == item ? PJ.elevated : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PJ.fill, in: Capsule())
    }
}

struct SettingsRow<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PJ.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(PJ.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, 2)
    }
}

struct QuietSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var ring = false
    var onEnded: (() -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let thumb = ring ? 14.0 : 16.0
            let t = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PJ.track)
                    .frame(height: ring ? 2 : 3)
                Circle()
                    .fill(PJ.elevated)
                    .overlay(
                        Circle().stroke(ring ? PJ.blue : PJ.line, lineWidth: ring ? 2.4 : 1)
                    )
                    .shadow(color: .black.opacity(ring ? 0 : 0.16), radius: ring ? 0 : 2, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: t * (width - thumb))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let x = min(max(0, gesture.location.x), width)
                        value = range.lowerBound + (x / width) * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in onEnded?() }
            )
        }
        .frame(height: 22)
    }
}

struct BandwidthSlider: View {
    @Binding var kbps: Int
    var onEnded: (() -> Void)? = nil
    private let stops = [0, 24, 64, 256, 1024, 2048]
    private let labels = ["Default", "24", "64", "256", "1,024", "Unlimited"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuietSlider(
                value: Binding(
                    get: { Double(nearestIndex) },
                    set: { kbps = stops[min(stops.count - 1, max(0, Int($0.rounded())))] }
                ),
                range: 0...Double(stops.count - 1),
                ring: true,
                onEnded: onEnded
            )
            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 11))
                        .foregroundStyle(index == 0 || index == labels.count - 1 ? PJ.secondary : PJ.tertiary)
                    if index < labels.count - 1 { Spacer() }
                }
            }
        }
    }

    private var nearestIndex: Int {
        stops.enumerated().min(by: { abs($0.element - kbps) < abs($1.element - kbps) })?.offset ?? 0
    }
}

private struct PointerHover: ViewModifier {
    @State private var over = false
    func body(content: Content) -> some View {
        content
            .opacity(over ? 0.86 : 1)
            .onHover { over = $0 }
    }
}

private extension View {
    func pointerHover() -> some View {
        modifier(PointerHover())
    }
}

struct CapsuleButton: View {
    var title: String
    var filled: Bool
    var action: () -> Void

    init(_ title: String, filled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    var body: some View {
        QuietCapsule(title: title, filled: filled, action: action)
    }
}

struct InkButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PJ.onFilled)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(configuration.isPressed ? PJ.ink.opacity(0.86) : PJ.filled, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(PJ.ink)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(PJ.surface, in: Capsule())
            .overlay(Capsule().stroke(PJ.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
