import LyricsKit
import SwiftUI

/// Full lyric sheet that keeps the current line in the upper third.
struct KaraokeView: View {
    let document: LyricsDocument
    let currentIndex: Int?
    /// Tapping a line jumps the song there (synced lyrics, playback control available).
    var onTapLine: ((LyricLine) -> Void)?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if document.syncType == .unsynced {
                        Text("These lyrics are not time-synced.")
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.accent)
                    }
                    ForEach(document.lines) { line in
                        Text(line.displayText)
                            .font(Theme.lyric(30))
                            .foregroundStyle(color(for: line))
                            .scaleEffect(line.id == currentIndex ? 1 : 0.96, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .onTapGesture {
                                guard document.syncType == .lineSynced, let onTapLine else { return }
                                onTapLine(line)
                            }
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 120)
            }
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.82), .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            .onChange(of: currentIndex, initial: true) { _, index in
                guard let index else { return }
                withAnimation(Theme.settle) { proxy.scrollTo(index, anchor: UnitPoint(x: 0, y: 0.32)) }
            }
            .animation(Theme.settle, value: currentIndex)
        }
    }

    private func color(for line: LyricLine) -> Color {
        guard document.syncType == .lineSynced, let currentIndex else { return Theme.ink.opacity(0.8) }
        if line.id == currentIndex { return Theme.ink }
        return line.id < currentIndex ? Theme.faint : Theme.dim
    }
}

/// One line, as large as the screen allows. Lines rise in from below.
struct FocusView: View {
    let engine: LyricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            if engine.document?.syncType == .unsynced {
                StatusLine(status: .ready, override: "Not synced. Switch to Karaoke to read along.")
            } else {
                Text(engine.currentLine?.displayText ?? "\u{266A}")
                    .font(Theme.lyric(44))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.5)
                    .id("now-\(engine.currentIndex ?? -1)")
                    .transition(.asymmetric(
                        insertion: .offset(y: 40).combined(with: .opacity),
                        removal: .offset(y: -40).combined(with: .opacity)
                    ))
                if let next = engine.nextLine {
                    Text(next.displayText)
                        .font(Theme.lyric(24))
                        .foregroundStyle(Theme.dim)
                        .id("next-\(next.id)")
                        .transition(.opacity)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .animation(Theme.settle, value: engine.currentIndex)
    }
}

/// The widget's layout at phone size: previous, current, next.
struct VerseView: View {
    let engine: LyricsEngine

    var body: some View {
        let document = engine.document
        let window = document?.window(around: engine.currentIndex, before: 1, after: 1) ?? []
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(engine.track?.name.uppercased() ?? "")
                    .font(Theme.label(12))
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                ForEach(window) { line in
                    Text(line.displayText)
                        .font(Theme.lyric(line.id == engine.currentIndex ? 28 : 20))
                        .foregroundStyle(line.id == engine.currentIndex ? Theme.ink : Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .background(Theme.raised, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 20)
            Spacer()
        }
        .animation(Theme.settle, value: engine.currentIndex)
    }
}

/// Empty state: a floating note. Tap it for a spin.
struct EmptyStage: View {
    let status: LyricsEngine.Status
    @State private var float = false
    @State private var spins = 0.0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 56, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .offset(y: float ? -8 : 0)
                .rotationEffect(.degrees(spins))
                .onTapGesture {
                    withAnimation(.spring(duration: 0.8, bounce: 0.35)) { spins += 360 }
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { float = true }
                }
            Text(title)
                .font(Theme.lyric(26))
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(Theme.label(15))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var title: String {
        switch status {
        case .signedOut: return "Spotify signed out"
        case .failed: return "Spotify is not answering"
        default: return "Play something"
        }
    }

    private var subtitle: String {
        switch status {
        case .signedOut: return "Reconnect from the menu to keep the lyrics flowing."
        case .failed(let message): return message
        default: return "Start a song in Spotify. The lyrics will find it."
        }
    }
}

struct StatusLine: View {
    let status: LyricsEngine.Status
    var override: String?

    var body: some View {
        Text(override ?? text)
            .font(Theme.lyric(24))
            .foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private var text: String {
        switch status {
        case .loadingLyrics: return "Finding lyrics"
        case .noLyrics: return "No lyrics for this one.\nEnjoy the music."
        default: return "\u{266A}"
        }
    }
}
