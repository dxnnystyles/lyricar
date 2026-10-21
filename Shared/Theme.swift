import SwiftUI

/// Phone-app shorthand for the selected `LyricTheme`. The root view is keyed on the
/// theme, so a style change re-renders everything with the new values.
enum Theme {
    static var style: LyricTheme { LyricTheme.current }

    static var stage: Color { style.base }
    static var raised: Color { style.raised }
    static var ink: Color { style.ink }
    static var dim: Color { style.dim }
    static var faint: Color { style.faint }
    static var accent: Color { style.accent }

    /// cubic-bezier(0.16, 1, 0.3, 1): fast start, gentle settle.
    static let settle = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.45)
    static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.22)

    static func lyric(_ size: CGFloat) -> Font { style.lyric(size) }
    static func label(_ size: CGFloat) -> Font { style.label(size) }
}
