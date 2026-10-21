import Foundation
import Testing
@testable import LyricsKit

@Suite struct LRCParserTests {
    @Test func parsesTimestampsMetadataAndMultiStampLines() {
        let lrc = """
        [ar:M83]
        [ti:Midnight City]
        [00:12.34]Waiting in a car
        [00:20.5][01:05.123]Chorus line
        [00:30:10]
        not a lyric line
        """
        let doc = LRCParser.parse(lrc, provider: "test")
        #expect(doc.syncType == .lineSynced)
        #expect(doc.lines.map(\.startMs) == [12_340, 20_500, 30_100, 65_123])
        #expect(doc.lines.map(\.text) == ["Waiting in a car", "Chorus line", "", "Chorus line"])
        #expect(doc.lines.map(\.id) == [0, 1, 2, 3])
        #expect(doc.lines[2].isInstrumental)
        #expect(doc.lines[2].displayText == "\u{266A}")
    }

    @Test func appliesOffsetTag() {
        let doc = LRCParser.parse("[offset:+500]\n[00:10.00]a\n[00:00.20]b", provider: "test")
        #expect(doc.lines.map(\.startMs) == [0, 9500])
        #expect(doc.lines.map(\.text) == ["b", "a"])
    }

    @Test func rejectsMalformedTimestamps() {
        #expect(LRCParser.parseTimestamp("ar:M83") == nil)
        #expect(LRCParser.parseTimestamp("01:75.00") == nil)
        #expect(LRCParser.parseTimestamp("1:02") == 62_000)
        #expect(LRCParser.parseTimestamp("00:01.5") == 1500)
    }

    @Test func hostileNumbersDoNotTrap() {
        #expect(LRCParser.parseTimestamp("9223372036854775807:00.00") == nil)
        #expect(LRCParser.parseTimestamp("-1:00.00") == nil)
        let doc = LRCParser.parse("[offset:-9223372036854775808]\n[00:10.00]a", provider: "test")
        #expect(doc.lines.map(\.startMs) == [610_000])
    }

    @Test func plainTextIsUnsynced() {
        let doc = LRCParser.plain("one\ntwo", provider: "test")
        #expect(doc.syncType == .unsynced)
        #expect(doc.lineIndex(at: 99_999) == nil)
    }
}

@Suite struct LyricsDocumentTests {
    let doc = LRCParser.parse("[00:01.00]a\n[00:05.00]b\n[00:09.00]c", provider: "test")

    @Test func findsActiveLine() {
        #expect(doc.lineIndex(at: 0) == nil)
        #expect(doc.lineIndex(at: 1000) == 0)
        #expect(doc.lineIndex(at: 4999) == 0)
        #expect(doc.lineIndex(at: 5000) == 1)
        #expect(doc.lineIndex(at: 600_000) == 2)
    }

    @Test func windowsAreClamped() {
        #expect(doc.window(around: 0, before: 2, after: 1).map(\.text) == ["a", "b"])
        #expect(doc.window(around: 2, before: 1, after: 3).map(\.text) == ["b", "c"])
        #expect(doc.window(around: nil, before: 2, after: 1).map(\.text) == ["a", "b"])
    }
}

@Suite struct PlaybackClockTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func sample(_ progress: Int, at offset: TimeInterval, playing: Bool = true, track: String = "x") -> PlaybackSample {
        PlaybackSample(trackID: track, progressMs: progress, durationMs: 200_000, isPlaying: playing, sampledAt: t0.addingTimeInterval(offset))
    }

    @Test func interpolatesWhilePlayingAndFreezesWhilePaused() {
        var clock = PlaybackClock()
        clock.ingest(sample(10_000, at: 0))
        #expect(clock.position(at: t0.addingTimeInterval(2.5)) == 12_500)
        clock.ingest(sample(12_500, at: 2.5, playing: false))
        #expect(clock.position(at: t0.addingTimeInterval(60)) == 12_500)
    }

    @Test func absorbsNoiseWithinUncertaintyButAcceptsSeeks() {
        var clock = PlaybackClock()
        clock.ingest(sample(10_000, at: 0))
        // 300 ms apart at equal precision (rtt 200 each): explained by noise, not a jump;
        // the newer estimate wins the tie.
        #expect(clock.ingest(sample(12_300, at: 2)) == false)
        #expect(clock.position(at: t0.addingTimeInterval(2)) == 12_300)
        #expect(clock.ingest(sample(90_000, at: 3)) == true)
        #expect(clock.position(at: t0.addingTimeInterval(3)) == 90_000)
    }

    @Test func newTrackIsAJump() {
        var clock = PlaybackClock()
        clock.ingest(sample(10_000, at: 0))
        #expect(clock.ingest(sample(10_000, at: 0, track: "y")) == true)
    }

    @Test func clampsToDuration() {
        var clock = PlaybackClock()
        clock.ingest(sample(199_000, at: 0))
        #expect(clock.position(at: t0.addingTimeInterval(30)) == 200_000)
        #expect(clock.trackStartDate() == t0.addingTimeInterval(-199))
    }
}

@Suite struct SnapshotTimelineTests {
    @Test func schedulesOneEntryPerUpcomingLine() {
        let start = Date(timeIntervalSince1970: 2_000_000)
        let doc = LRCParser.parse("[00:01.00]a\n[00:05.00]b\n[00:09.00]c", provider: "test")
        let snapshot = LyricsSnapshot(trackName: "t", artist: "a", provider: "p", document: doc, isPlaying: true,
                                      durationMs: 20_000, trackStartDate: start, pausedPositionMs: 0, updatedAt: start)
        let now = start.addingTimeInterval(3)
        let timeline = snapshot.timeline(from: now)
        #expect(timeline.map(\.lineIndex) == [0, 1, 2])
        #expect(timeline.map(\.date) == [now, start.addingTimeInterval(5), start.addingTimeInterval(9)])
    }

    @Test func pausedSnapshotHasOneEntry() {
        var snapshot = LyricsSnapshot.placeholder
        snapshot.isPlaying = false
        #expect(snapshot.timeline(from: Date()).map(\.lineIndex) == [1])
    }

    @Test func roundTripsThroughDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "lyricar.tests.\(UUID())"))
        LyricsSnapshot.placeholder.save(to: defaults)
        #expect(LyricsSnapshot.load(from: defaults) == LyricsSnapshot.placeholder)
    }
}

@Suite struct DecodingTests {
    @Test func decodesCurrentlyPlaying() throws {
        let json = """
        {"progress_ms":42000,"is_playing":true,"currently_playing_type":"track",
         "item":{"id":"abc","name":"Midnight City","duration_ms":243000,
                 "artists":[{"name":"M83"}],"album":{"name":"Hurry Up","images":[{"url":"https://i.scdn.co/x"}]}}}
        """
        let at = Date(timeIntervalSince1970: 5)
        let now = try #require(try SpotifyClient.decode(Data(json.utf8), sampledAt: at))
        #expect(now.track.name == "Midnight City")
        #expect(now.track.artistLine == "M83")
        #expect(now.sample.progressMs == 42_000)
        #expect(now.sample.sampledAt == at)
    }

    @Test func adsAreNotTracks() throws {
        let json = #"{"progress_ms":1,"is_playing":true,"currently_playing_type":"ad","item":null}"#
        #expect(try SpotifyClient.decode(Data(json.utf8), sampledAt: Date()) == nil)
    }

    @Test func picksSyncedRecordWithinDuration() {
        let records = [
            LRCLibRecord(duration: 300, instrumental: false, plainLyrics: "x", syncedLyrics: "[00:01.00]wrong"),
            LRCLibRecord(duration: 241, instrumental: false, plainLyrics: "x", syncedLyrics: nil),
            LRCLibRecord(duration: 242, instrumental: false, plainLyrics: "x", syncedLyrics: "[00:01.00]right"),
        ]
        #expect(LRCLibClient.bestMatch(records, durationMs: 243_000)?.syncedLyrics == "[00:01.00]right")
        #expect(LRCLibClient.cleanTitle("Song - 2011 Remaster") == "Song")
        #expect(LRCLibClient.cleanTitle("Song (feat. X)") == "Song")
    }
}
