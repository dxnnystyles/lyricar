# The precision-weighted playback clock

Spotify's current-playing response includes a progress value, but the exact
instant when Spotify sampled it is unknown. Lyricar records the midpoint of
the request as the sample time. Half the round trip is the uncertainty on each
side of that midpoint.

```text
request starts                         response finishes
      |--------------------------------------|
                       ^
                 sample timestamp
                 uncertainty: +/- RTT/2
```

The sample implies a track start:

```text
estimated track start = sample timestamp - reported progress
```

While playing, the clock predicts position as the current time minus that
estimated track start. A more precise response can correct a slow first poll
without making lyrics wait for the next poll.

## Choosing an anchor

For each playing sample, the clock compares its estimated track start with the
current best anchor. If the disagreement is too large to explain by network
uncertainty, it treats the change as a seek. Otherwise, it adds the sample,
discards anchors older than 20 seconds, and selects the anchor with the lowest
uncertainty. If uncertainties tie, the newest anchor wins.

The playing seek threshold is:

```text
absolute start-time disagreement > new uncertainty + best uncertainty + 150 ms
```

Crossing that threshold resets the clock to the new sample and reports a jump,
so lyric timelines can be rebuilt immediately. A new track or a play-state
change also resets the clock and reports a jump. While paused, Spotify's
reported position is treated as exact; a paused-to-paused change greater than
150 ms reports a seek.

## Test examples

[SyncPrecisionTests](../Packages/LyricsKit/Tests/LyricsKitTests/SyncPrecisionTests.swift)
uses synthetic samples to show the rule: an initially slow, 900 ms round trip
with 300 ms lag is corrected by 80 ms samples; a 1,200 ms response with 400 ms
error does not displace a 60 ms anchor; and a jump to 120 seconds is applied
immediately. The implementation is in
[PlaybackClock](../Packages/LyricsKit/Sources/LyricsKit/PlaybackClock.swift).
