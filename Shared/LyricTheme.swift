import AppIntents
import LyricsKit
import SwiftUI

/// Visual styles shared by the phone app, widgets, the Live Activity and the CarPlay
/// stage card. Each style owns palette, type and how progress is drawn.
enum LyricTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case midnight
    case motorsport
    /// Raw value kept from an earlier name so stored selections still decode.
    case nightDrive = "idrive"
    case panoramic
    case sport
    case luxe
    case neon
    case daylight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .motorsport: return "Motorsport"
        case .nightDrive: return "Night Drive"
        case .panoramic: return "Panoramic"
        case .sport: return "Sport"
        case .luxe: return "Luxe"
        case .neon: return "Neon"
        case .daylight: return "Daylight"
        }
    }

    var tagline: String {
        switch self {
        case .midnight: return "Amber on black"
        case .motorsport: return "Tricolor stripe on graphite"
        case .nightDrive: return "Black glass, blue glow"
        case .panoramic: return "Light band, gradient line"
        case .sport: return "Carbon and redline"
        case .luxe: return "Champagne serif"
        case .neon: return "Synthwave glow"
        case .daylight: return "Readable in sun"
        }
    }

    enum ProgressStyle { case bar, stripe, redline, hairline, glow }

    // MARK: Palette

    var background: LinearGradient {
        switch self {
        case .midnight: return Self.flat(0x0B0B0F)
        case .motorsport: return LinearGradient(colors: [Color(hex: 0x24272C), Color(hex: 0x0B0C0E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .nightDrive: return LinearGradient(colors: [Color(hex: 0x0B1A30), Color(hex: 0x02040A), Color(hex: 0x000000)], startPoint: .topTrailing, endPoint: .bottomLeading)
        case .panoramic: return LinearGradient(colors: [Color(hex: 0xF4F4F1), Color(hex: 0xE6E8EA)], startPoint: .top, endPoint: .bottom)
        case .sport: return LinearGradient(colors: [Color(hex: 0x1A1A1A), Color(hex: 0x050505)], startPoint: .top, endPoint: .bottom)
        case .luxe: return LinearGradient(colors: [Color(hex: 0x1C1712), Color(hex: 0x0D0A08)], startPoint: .top, endPoint: .bottom)
        case .neon: return LinearGradient(colors: [Color(hex: 0x2A0845), Color(hex: 0x0B0118)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .daylight: return Self.flat(0xF7F7F4)
        }
    }

    /// Solid color for places that cannot take a gradient (Live Activity tint, CarPlay).
    var base: Color {
        switch self {
        case .midnight: return Color(hex: 0x0B0B0F)
        case .motorsport: return Color(hex: 0x17191D)
        case .nightDrive: return Color(hex: 0x03060C)
        case .panoramic: return Color(hex: 0xF0F1EF)
        case .sport: return Color(hex: 0x0D0D0D)
        case .luxe: return Color(hex: 0x15110D)
        case .neon: return Color(hex: 0x16032A)
        case .daylight: return Color(hex: 0xF7F7F4)
        }
    }

    var isLight: Bool { self == .daylight || self == .panoramic }
    var ink: Color { isLight ? Color(hex: 0x15171A) : .white }
    var dim: Color { ink.opacity(isLight ? 0.45 : 0.38) }
    var faint: Color { ink.opacity(0.16) }
    var raised: Color { isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.07) }

    var accent: Color {
        switch self {
        case .midnight: return Color(hex: 0xFFB547)
        case .motorsport: return Color(hex: 0x008AC9)
        case .nightDrive: return Color(hex: 0x1C69D4)
        case .panoramic: return Color(hex: 0x0A6FD8)
        case .sport: return Color(hex: 0xFF2D2D)
        case .luxe: return Color(hex: 0xD8B878)
        case .neon: return Color(hex: 0xFF4FD8)
        case .daylight: return Color(hex: 0x0A5CFF)
        }
    }

    /// Motorsport's tricolor; other styles repeat their accent.
    var stripe: [Color] {
        switch self {
        // Racing tricolor: light blue, violet, red.
        case .motorsport: return [Color(hex: 0x008AC9), Color(hex: 0x2B115A), Color(hex: 0xF11A22)]
        case .panoramic: return [Color(hex: 0x37D5E8), Color(hex: 0x0A6FD8)]
        case .neon: return [Color(hex: 0x00E5FF), Color(hex: 0xFF4FD8)]
        default: return [accent]
        }
    }

    var progressStyle: ProgressStyle {
        switch self {
        case .midnight, .daylight: return .bar
        case .motorsport: return .stripe
        case .nightDrive: return .glow
        case .panoramic: return .stripe
        case .sport: return .redline
        case .luxe: return .hairline
        case .neon: return .glow
        }
    }

    var uppercaseLabels: Bool { self == .motorsport || self == .sport || self == .nightDrive }

    // MARK: Type

    func lyric(_ size: CGFloat) -> Font {
        switch self {
        case .midnight, .daylight:
            return .system(size: size, weight: .heavy, design: .rounded)
        case .motorsport:
            return .custom("BarlowCondensed-ExtraBoldItalic", size: size * 1.08)
        case .nightDrive:
            return .custom("Barlow-Light", size: size * 1.04)
        case .panoramic:
            return .custom("Barlow-Medium", size: size)
        case .sport:
            return .system(size: size, weight: .black).width(.compressed)
        case .luxe:
            return .system(size: size, weight: .semibold, design: .serif)
        case .neon:
            return .system(size: size * 0.92, weight: .bold, design: .monospaced)
        }
    }

    func label(_ size: CGFloat) -> Font {
        switch self {
        case .motorsport: return .custom("BarlowCondensed-SemiBold", size: size * 1.1)
        case .nightDrive, .panoramic: return .custom("Barlow-Medium", size: size)
        case .sport: return .system(size: size, weight: .bold).width(.condensed)
        case .luxe: return .system(size: size, weight: .medium, design: .serif)
        case .neon: return .system(size: size, weight: .semibold, design: .monospaced)
        default: return .system(size: size, weight: .semibold, design: .rounded)
        }
    }

    /// Glow for neon text; nothing for the others.
    var glow: Color {
        switch self {
        case .neon: return accent.opacity(0.85)
        case .nightDrive: return accent.opacity(0.55)
        default: return .clear
        }
    }

    // MARK: Selection shared through the App Group

    static let storageKey = "lyricTheme"

    /// Read once per process, then cached: phone views ask for it on every frame.
    /// Only the app opts in; the widget extension process can outlive a style change
    /// made in the app, so it always re-reads the shared value.
    nonisolated(unsafe) private static var cached: LyricTheme?
    nonisolated(unsafe) static var cachingEnabled = false

    static var current: LyricTheme {
        get {
            if cachingEnabled, let cached { return cached }
            let stored = UserDefaults(suiteName: LyricsSnapshot.appGroup)?.string(forKey: storageKey).flatMap(LyricTheme.init(rawValue:)) ?? .midnight
            cached = stored
            return stored
        }
        set {
            cached = newValue
            UserDefaults(suiteName: LyricsSnapshot.appGroup)?.set(newValue.rawValue, forKey: storageKey)
        }
    }

    private static func flat(_ hex: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: hex)], startPoint: .top, endPoint: .bottom)
    }
}

extension LyricTheme: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static let caseDisplayRepresentations: [LyricTheme: DisplayRepresentation] = [
        .midnight: "Midnight",
        .motorsport: "Motorsport",
        .nightDrive: "Night Drive",
        .panoramic: "Panoramic",
        .sport: "Sport",
        .luxe: "Luxe",
        .neon: "Neon",
        .daylight: "Daylight",
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Track progress in the style's own shape. Driven by `timerInterval` while playing,
/// so it animates in widgets and Live Activities without updates.
struct ThemedProgress: View {
    let theme: LyricTheme
    let start: Date
    let end: Date
    let isPlaying: Bool
    let fraction: Double

    var body: some View {
        switch theme.progressStyle {
        case .stripe:
            VStack(spacing: 3) {
                bar.tint(theme.stripe[0])
                HStack(spacing: 2) {
                    ForEach(Array(theme.stripe.enumerated()), id: \.offset) { _, color in
                        Rectangle().fill(color).frame(height: 3)
                    }
                }
                .clipShape(.rect(cornerRadius: 1))
            }
        case .redline:
            HStack(spacing: 6) {
                bar.tint(theme.accent)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        case .hairline:
            bar.tint(theme.accent).scaleEffect(x: 1, y: 0.5, anchor: .center)
        case .glow:
            bar.tint(theme.accent).shadow(color: theme.accent, radius: 4)
        case .bar:
            bar.tint(theme.accent)
        }
    }

    @ViewBuilder private var bar: some View {
        if isPlaying, start < end {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.linear)
        } else {
            // Drawn by hand: the static ProgressView ignores the style tint.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.faint)
                    Capsule().fill(theme.accent).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Ring gauge. Timer-driven while playing; drawn by hand when static.
struct ThemedRing: View {
    let theme: LyricTheme
    let start: Date?
    let end: Date?
    let isPlaying: Bool
    let fraction: Double
    var lineWidth: CGFloat = 8

    var body: some View {
        if isPlaying, let start, let end, start < end {
            ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                .progressViewStyle(.circular)
                .tint(theme.accent)
        } else {
            ZStack {
                Circle().stroke(theme.faint, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: theme.glow, radius: 5)
            }
        }
    }
}

/// Portrait card face for CarPlay's card element (a small, tall tile): style mark,
/// the current line as large as fits, the next line, the track. No overlay text needed.
struct LyricCardFace: View {
    let theme: LyricTheme
    let trackName: String
    let current: String
    let next: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if StripeMark.has(theme) {
                StripeMark(theme: theme, height: 11)
            } else {
                Capsule().fill(theme.accent).frame(width: 18, height: 4)
            }
            Spacer(minLength: 0)
            Text(current)
                .font(theme.lyric(24))
                .foregroundStyle(theme.ink)
                .shadow(color: theme.glow, radius: 5)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
            if let next {
                Text(next)
                    .font(theme.lyric(14))
                    .foregroundStyle(theme.dim)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            // The bottom quarter of the tile is covered by CarPlay's tint strip.
            Spacer(minLength: 28)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.background)
    }
}

/// The lyric card: used as the CarPlay stage image, as the large widget body and in
/// the style picker. Pure function of its inputs, so ImageRenderer can draw it.
struct LyricCard: View {
    let theme: LyricTheme
    let trackName: String
    let artist: String
    let previous: String?
    let current: String
    let next: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 6) {
                if StripeMark.has(theme) {
                    StripeMark(theme: theme, height: 13)
                } else {
                    Circle().fill(theme.accent).frame(width: 7, height: 7).shadow(color: theme.glow, radius: 4)
                }
                Text(theme.uppercaseLabels ? trackName.uppercased() : trackName)
                    .font(theme.label(compact ? 11 : 13))
                    .tracking(theme.uppercaseLabels ? 1.2 : 0)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(artist)
                    .font(theme.label(compact ? 10 : 12))
                    .foregroundStyle(theme.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let previous, !compact {
                Text(previous).font(theme.lyric(16)).foregroundStyle(theme.faint).lineLimit(1)
            }
            Text(current)
                .font(theme.lyric(compact ? 20 : 28))
                .foregroundStyle(theme.ink)
                .shadow(color: theme.glow, radius: 6)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
            if let next {
                Text(next).font(theme.lyric(compact ? 13 : 17)).foregroundStyle(theme.dim).lineLimit(compact ? 1 : 2)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 12 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.background)
    }
}


/// The style's signature mark. Motorsport: the three M stripes on a light badge plate,
/// as on the cars (the official violet disappears on dark surfaces without it).
/// Panoramic: its gradient line. Others: nil, callers fall back to their own glyph.
struct StripeMark: View {
    let theme: LyricTheme
    var height: CGFloat = 13

    var body: some View {
        switch theme {
        case .motorsport:
            HStack(spacing: height * 0.12) {
                ForEach(Array(theme.stripe.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color).frame(width: height * 0.32, height: height)
                }
            }
            .rotationEffect(.degrees(-0.001))
            .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.28, d: 1, tx: height * 0.14, ty: 0))
            .padding(.horizontal, height * 0.28)
            .padding(.vertical, height * 0.16)
            .background(Color(white: 0.94), in: .rect(cornerRadius: height * 0.18))
        case .panoramic, .neon:
            Capsule()
                .fill(LinearGradient(colors: theme.stripe, startPoint: .leading, endPoint: .trailing))
                .frame(width: height * 1.9, height: height * 0.28)
        default:
            EmptyView()
        }
    }

    static func has(_ theme: LyricTheme) -> Bool { theme == .motorsport || theme == .panoramic || theme == .neon }
}
