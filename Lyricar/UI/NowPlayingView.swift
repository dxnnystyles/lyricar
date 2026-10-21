import LyricsKit
import SwiftUI

enum LyricMode: String, CaseIterable, Identifiable {
    case karaoke = "Karaoke"
    case focus = "Focus"
    case verse = "Verse"

    var id: String { rawValue }
}

struct NowPlayingView: View {
    let model: AppModel
    @AppStorage("lyricMode") private var mode: LyricMode = .karaoke
    @State private var direction: Edge = .trailing

    private var engine: LyricsEngine { model.engine }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                content
                    .id(mode)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction).combined(with: .opacity),
                        removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            controls
        }
        .animation(Theme.settle, value: engine.track?.id)
        .animation(Theme.settle, value: engine.status)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            AsyncImage(url: engine.track?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.raised
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.track?.name ?? "Lyricar")
                    .font(Theme.label(17))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.interpolate)
                Text(engine.track?.artistLine ?? (model.connectionNote ?? "Connected to Spotify"))
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.dim)
                    .contentTransition(.interpolate)
            }
            .lineLimit(1)
            Spacer()
            OpenInSpotifyButton(track: engine.track)
            Menu {
                Picker("Style", systemImage: "paintpalette", selection: Binding(get: { model.theme }, set: { model.theme = $0 })) {
                    ForEach(LyricTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.menu)
                Button("Resync", systemImage: "arrow.triangle.2.circlepath") { engine.refreshNow() }
                Section("Lyrics timing\(engine.offsetMs == 0 ? "" : String(format: " (%+.2f s)", Double(engine.offsetMs) / 1000))") {
                    Button("Lyrics are late", systemImage: "forward") { engine.nudge(byMs: 250) }
                    Button("Lyrics are early", systemImage: "backward") { engine.nudge(byMs: -250) }
                    if engine.offsetMs != 0 {
                        Button("Reset timing", systemImage: "arrow.uturn.backward") { engine.nudge(byMs: -engine.offsetMs) }
                    }
                }
                Toggle("Stay in sync in background", isOn: Binding(get: { model.backgroundSync }, set: { model.backgroundSync = $0 }))
                Button("Disconnect Spotify", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await model.signOut() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.dim)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if engine.track == nil {
            EmptyStage(status: engine.status)
        } else if let document = engine.document, !document.lines.isEmpty {
            switch mode {
            case .karaoke:
                KaraokeView(document: document, currentIndex: engine.currentIndex,
                            onTapLine: engine.canControl ? { engine.seek(toLine: $0) } : nil)
            case .focus: FocusView(engine: engine)
            case .verse: VerseView(engine: engine)
            }
        } else {
            StatusLine(status: engine.status)
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            TrackProgress(engine: engine)
            if engine.canControl, engine.track != nil {
                TransportControls(engine: engine)
            }
            HStack(spacing: 12) {
                ModePicker(mode: Binding(
                    get: { mode },
                    set: { new in
                        let all = LyricMode.allCases
                        direction = (all.firstIndex(of: new) ?? 0) > (all.firstIndex(of: mode) ?? 0) ? .trailing : .leading
                        withAnimation(Theme.settle) { mode = new }
                    }
                ))
                LiveActivityButton(model: model)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Pieces

struct TrackProgress: View {
    let engine: LyricsEngine

    var body: some View {
        if let track = engine.track, let start = engine.trackStartDate() {
            let end = start.addingTimeInterval(Double(track.durationMs) / 1000)
            Group {
                if engine.isPlaying, start < end {
                    ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                } else {
                    ProgressView(value: Double(engine.positionMs() ?? 0), total: Double(max(track.durationMs, 1)))
                }
            }
            .tint(Theme.accent)
            .progressViewStyle(.linear)
        }
    }
}

struct ModePicker: View {
    @Binding var mode: LyricMode
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LyricMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Text(option.rawValue)
                        .font(Theme.label(15))
                        .foregroundStyle(option == mode ? Theme.stage : Theme.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background {
                            if option == mode {
                                Capsule().fill(Theme.ink).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(4)
        .background(Theme.raised, in: .capsule)
    }
}

struct LiveActivityButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            withAnimation(Theme.settle) { model.liveActivityOn.toggle() }
        } label: {
            Image(systemName: model.liveActivityOn ? "dot.radiowaves.left.and.right" : "rectangle.badge.plus")
                .font(.system(size: 18, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(model.liveActivityOn ? Theme.stage : Theme.dim)
                .frame(width: 50, height: 50)
                .background(model.liveActivityOn ? Theme.accent : Theme.raised, in: .circle)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(model.liveActivityOn ? "Stop Live Activity" : "Show on Lock Screen and CarPlay")
    }
}
