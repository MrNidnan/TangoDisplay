# Proposal for track padding and silence skipping

Add **Affix Silence** and **Skip Silence** to TangoDisplay’s built-in player. The first gives the DJ an exact amount of extra silence before or after a track. The second shortens long quiet passages in the recording and continues at the next audible sound in the same song. Keep the existing **Auto-gap** option for sets where the DJ wants a minimum separation between tracks.

## Comparison

| Control | What it does | When to use it |
| --- | --- | --- |
| **Auto-gap**, current | Estimates the end silence of the outgoing track and the start silence of the next track. It adds only the remaining amount needed to reach a minimum gap, as a preroll on the incoming track. | Keep a consistent minimum separation across recordings with different amounts of embedded silence. |
| **Track Start & End Time**, current | Applies manually chosen start and end positions to a setlist entry. | Make an editorial decision about a particular recording, such as removing an introduction even when it contains sound. |
| **Affix Silence**, proposed | Adds exact lead-in and lead-out durations in milliseconds to each track pass. The calculation does not depend on the audio signal. | Allow a deliberate lead-in or hold the floor after a song ends. |
| **Skip Silence**, proposed | Shortens qualifying quiet passages inside the playable part of a recording, including its start, middle and end. It preserves short pauses and resumes at the next audible part of the current song. | Remove long dead air in transfers or recordings that contain a long silent tail. |

The current analyzer checks up to ten seconds at each end in approximately ten-millisecond windows, using a fixed quantized peak threshold. Auto-gap keys its prepared analysis to the outgoing and incoming rows and clamps the credited silence to the trims. Its current calculation is `max(0, minimum − outgoing silence − incoming silence)`. The implementation has no mechanism for detecting a quiet passage in the middle of the file. [AudioSilenceAnalyzer](Sources/TangoDisplay/Services/AudioSilenceAnalyzer.swift) · [PreparedAutoGap](Sources/TangoDisplayCore/Audio/PreparedAutoGap.swift) · [Built-in player](Sources/TangoDisplay/Services/LocalPlayerSource.swift)

## 1. Affix Silence

Follow the component’s user-facing behavior with independent **Before track (ms)** and **After track (ms)** controls. Zero disables padding at that edge. The numbers represent extra silence, so 500 ms before a file with a 700 ms silent introduction normally gives 1,200 ms before the music starts. Scope the feature to the built-in player and leave audio files unchanged. [foobar2000 Affix silence](https://www.foobar2000.org/components/view/foo_dsp_silence)

- Default both values to 0 ms. Apply them on a new track pass, including a repeat. A seek, resume, or output-device recovery continues the current pass without scheduling the lead-in again.
- Schedule lead-out after the last playable frame has drained. Keep the outgoing track current during its lead-out. An explicit stop or immediate skip cancels any remaining padding so the DJ retains transport control.
- Use global controls for the first release. Add row overrides only if DJs need different padding for particular tracks often enough to justify the extra controls.

## 2. Skip Silence

Follow Skip Silence DSP’s documented behavior of advancing through sustained silence and smoothing the splice. Offer **Skip after (ms)** and **Silence threshold (dBFS)**. Start with the feature off, and suggest 1,500 ms and −55 dBFS as editable initial values. These settings and the detector below are proposed TangoDisplay defaults. [foobar2000 Skip Silence DSP by Case](https://foobar.hyv.fi/?view=foo_dsp_skip_silence)

- A quiet run qualifies once **every** channel stays at or below the threshold for the configured duration. Measure the peak in short PCM windows before volume, ReplayGain, EQ and restoration so changing the output level leaves the decision stable. Preserve audio when either stereo channel crosses the threshold.
- Play up to the configured amount of each qualifying quiet run, then jump to just before the first audible window. Use a short transition within the quiet material where possible to avoid clicks and protect the next attack. For example, a 2,400 ms quiet run with a 1,500 ms setting retains about 1,500 ms, then resumes the current song before the next sound.
- Apply the same rule to leading, internal and trailing silence inside the manual trim range. If a quiet tail reaches the trimmed end and there is no next sound in the file, finish the track through the normal end-of-track path. Let repeat, stop-after, and cortina handling decide what happens next. If the entire trimmed track is quiet, leave it playing as scheduled in the first release so a deliberately silent file remains usable.
- Leave Skip Silence off for current installations and exclude cortinas and marked performances by default. A threshold can mistake quiet music for dead air, especially on shellac transfers and sparse arrangements.

## How the controls work together

Apply manual trim, then shorten qualifying silence in the recorded audio, then add the explicit before/after padding. With Auto-gap enabled, credit the **remaining** recorded edge silence and the **scheduled** affix padding toward the minimum. Auto-gap fills any shortfall. This keeps explicit padding audible and avoids adding the same separation twice.

For example, if the outgoing file has 300 ms of retained trailing silence, the incoming file has 200 ms of retained leading silence, and affix adds 400 ms after plus 100 ms before, the planned separation is 1,000 ms. A 1,500 ms Auto-gap minimum adds a further 500 ms. With Auto-gap off, the separation stays at 1,000 ms.

### Optional maximum between tracks

Implemented as an optional built-in-player control under **Player › Silence & Gaps**. The standalone Affix Silence and Skip Silence controls are still proposed.

Add **Maximum gap** as an optional Auto-gap setting. For a **2,500–3,500 ms** range, add silence when the planned transition is under 2,500 ms, leave it alone within the range, and shorten the recorded silence at the track edges when it would exceed 3,500 ms. For example, a 2,000 ms gap becomes 2,500 ms, a 3,000 ms gap stays as recorded, and a 6,000 ms gap becomes 3,500 ms. This setting works independently of Skip Silence inside songs.

Measure the gap from the last audible sound of the outgoing track to the first audible sound of the incoming track. After manual trim and any enabled Skip Silence, apply the cap to quiet edge material only. Shorten the incoming silence first, then shorten the outgoing tail if needed. Plan that tail before it plays, since the player cannot reclaim silence the audience has already heard. Preserve the next attack and honor explicit affix padding. If the affix padding alone exceeds the maximum, flag the conflict in settings. If edge analysis is unavailable in time, play on schedule using the existing minimum-gap behavior.

Put these controls under **Player › Silence & Gaps**. Use **Minimum gap**, **Maximum gap**, **Add before/after**, and **Skip after** as the labels so the DJ can distinguish the transition range, fixed padding and a threshold-driven edit. Leave the maximum off for existing setups and preserve the current first-track, per-row and manual-stop Auto-gap options. Keep manual trim in the waveform editor.

## Implementation and acceptance

1. **Ship Affix Silence first.** Extend the existing silent-buffer scheduling into leading and trailing segments. Update completion handling so lead-out completes exactly once, even after a seek or skip. Preserve the current source-file position for waveform and trim controls.
2. **Add Skip Silence behind its toggle.** Scan decoded chunks off the main thread, record only qualifying frame ranges, and key cached results by file identity and detector settings. Precompute for upcoming tracks where possible. Until analysis is ready, play the original track on time. In the first release, apply completed analysis on the next track pass. Keep source-frame position separate from played duration so a forward jump does not trigger early played-marking or the playback watchdog.
3. **Unify transition timing.** Derive the effective trailing silence, leading silence, and padding from the same playback plan. Test the order with trim and both features enabled, plus a reorder or immediate skip while a transition is prepared.

Acceptance tests should cover exact lead-in and lead-out frame counts on mono and stereo, short pauses that remain untouched, a below-threshold internal run followed by audio on only one channel, a trimmed silent tail, and an entirely silent file. For the maximum gap, cover transitions below, inside, and above the 2,500–3,500 ms range, including a long outgoing tail and padding that exceeds the cap. Exercise repeat, stop-after, cortina, pause/resume, seeking, and explicit skip. With the new controls disabled, existing Auto-gap and trim behavior should pass the same regression tests.
