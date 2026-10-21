import Foundation

/// Public, keyless lyrics database (https://lrclib.net). Returns LRC text.
public struct LRCLibClient: Sendable {
    let session: URLSession
    let base = URL(string: "https://lrclib.net/api")!
    static let userAgent = "Lyricar/0.1 (https://github.com/noluyorAbi/lyricar)"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Tries, in order: exact match with album, exact match without album (LRCLIB answers
    /// 503 for some album lookups it has not cached), then a fuzzy search.
    /// Returns nil when every source answered and none had lyrics. Throws only when
    /// every attempt failed, so the caller can retry instead of caching a miss.
    public func lyrics(for track: SpotifyTrack) async throws -> LyricsDocument? {
        let artist = track.artists.first ?? ""
        let attempts: [() async throws -> LyricsDocument?] = [
            { try await get(track: track.name, artist: artist, album: track.album, durationMs: track.durationMs) },
            { try await get(track: track.name, artist: artist, album: nil, durationMs: track.durationMs) },
            // Remasters and featured-artist titles often miss the exact lookup.
            { try await search(track: Self.cleanTitle(track.name), artist: artist, durationMs: track.durationMs) },
        ]

        var lastError: Error?
        var anyAnswered = false
        for attempt in attempts {
            do {
                if let document = try await attempt() { return document }
                anyAnswered = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        if !anyAnswered, let lastError { throw lastError }
        return nil
    }

    func get(track: String, artist: String, album: String?, durationMs: Int) async throws -> LyricsDocument? {
        var components = URLComponents(url: base.appendingPathComponent("get"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(durationMs / 1000)),
        ]
        if let album, !album.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "album_name", value: album))
        }
        guard let data = try await fetch(components.url!) else { return nil }
        return Self.document(from: try JSONDecoder().decode(LRCLibRecord.self, from: data))
    }

    func search(track: String, artist: String, durationMs: Int) async throws -> LyricsDocument? {
        var components = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        guard let data = try await fetch(components.url!) else { return nil }
        let records = try JSONDecoder().decode([LRCLibRecord].self, from: data)
        return Self.bestMatch(records, durationMs: durationMs).flatMap(Self.document(from:))
    }

    private func fetch(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw SpotifyError.http(status) }
        return data
    }

    /// Prefers synced lyrics whose duration is within 3 s of the Spotify track.
    static func bestMatch(_ records: [LRCLibRecord], durationMs: Int) -> LRCLibRecord? {
        let seconds = Double(durationMs) / 1000
        let close = records.filter { abs(($0.duration ?? seconds) - seconds) <= 3 }
        return close.first { $0.syncedLyrics?.isEmpty == false }
            ?? close.first { $0.plainLyrics?.isEmpty == false }
    }

    static func document(from record: LRCLibRecord) -> LyricsDocument? {
        if record.instrumental == true {
            return LyricsDocument(syncType: .unsynced, lines: [LyricLine(id: 0, startMs: 0, text: "")], provider: "LRCLIB")
        }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            return LRCParser.parse(synced, provider: "LRCLIB")
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return LRCParser.plain(plain, provider: "LRCLIB")
        }
        return nil
    }

    /// "Song - 2011 Remaster" and "Song (feat. X)" become "Song".
    static func cleanTitle(_ title: String) -> String {
        var result = title
        if let range = result.range(of: " - ") { result = String(result[..<range.lowerBound]) }
        if let range = result.range(of: " (feat", options: .caseInsensitive) { result = String(result[..<range.lowerBound]) }
        if let range = result.range(of: " (with", options: .caseInsensitive) { result = String(result[..<range.lowerBound]) }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

struct LRCLibRecord: Decodable {
    let duration: Double?
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}
