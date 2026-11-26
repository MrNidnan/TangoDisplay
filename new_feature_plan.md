# TangoDisplay engineering review and feature plan

Reviewed `main` at `af5d464` on 26 November 2026. The review focused on live playback, saved setlists, tag editing, and the development and release workflow. TangoDisplay targets macOS 13 and uses a SwiftUI executable, a shared logic library, an Objective-C/C++ bridge, and a custom test runner.

## Development setup and verification

- The Apple Silicon Mac already has Xcode 27.2, Swift 6.4.2, the macOS 27.2 SDK, Git, Clang, and the packaging tools used by `Install.sh`. No developer tools needed installation. SwiftPM manages the pinned Sparkle 2.9.2 and CXXTagLib 2.3.2 dependencies. [Package manifest](Package.swift) · [Dependency lockfile](Package.resolved)
- The default build hit a permissions error in the user-level Clang module cache. With the compiler and SwiftPM caches redirected to the checkout, `swift build`, `swift run TangoDisplayTests`, and `swift run TangoDisplay` all reached dependency resolution. The session could not resolve `github.com` and had no usable local copies of the two dependencies. The full build, suite, and GUI launch remain unverified.
- A temporary offline harness compiled the core and vendored restoration code on arm64. **153 checks passed**, including the restoration DSP self-test, Audio Unit registration, symbol checks, and settings tests. The two TagLib tests require the missing package. The first restoration graph test aborted in `AVAudioPlayerNode.init` during the offline harness run, before the custom Audio Unit was attached. Both graph tests were omitted from the passing count. Rerun them through the normal test target in a macOS desktop session before attributing the failure to TangoDisplay. Swift source parsing and `bash -n Install.sh` also passed. [Test runner](Tests/TangoDisplayTests/main.swift#L1156) · [Restoration tests](Tests/TangoDisplayTests/RestorationTests.swift#L23)

## P0 — Report playback only after it starts

**Finding.** In the built-in player, `loadEntry` catches file-open and engine-start errors, clears `audioFile`, and continues by marking the entry as playing. Several callers also set `isActivePlaying` after `startPlayerNode` returns, even when it returns `false`. The dancer display can therefore say that a track is playing while the audio is silent. This follows from the source. Live output recovery could not be exercised in this session. [Load failure](Sources/TangoDisplay/Services/LocalPlayerSource.swift#L1127) · [Guarded start](Sources/TangoDisplay/Services/LocalPlayerSource.swift#L941) · [Play and display updates](Sources/TangoDisplay/Services/LocalPlayerSource.swift#L732)

**Change.** Commit the playing state after successful scheduling and startup. When a track fails to load or stops unexpectedly during playback, flag its row and advance to the next playable track. Preserve repeat and stop-after behavior for normal track endings. Wait for the output device when the entire audio output is unavailable.

**Acceptance.** With a missing, unreadable, or stalled track followed by a playable track, TangoDisplay stays open and plays the following track. After a full app crash, reopening restores the saved setlist and waits for the DJ to press Play. Reconnecting the output or relinking a file allows retry.

## P0 — Recover setlists when media goes offline

**Finding.** Setlist loading drops every saved row whose path fails `fileExists`. Starting with a disconnected drive therefore hides its rows, and the next successful save can remove them from `setlist.json`. The save path also discards write errors, so the UI can accept edits that never reach disk. [Setlist persistence](Sources/TangoDisplay/Services/SetlistManager.swift#L351)

**Change.** Preserve saved rows and show unavailable media in the setlist. Add **Retry** for volumes that return and **Relink** for moved files. Keep row IDs, order, and per-track overrides when a file is relinked. Move persistence behind a small store with an injectable location, keep atomic writes, and surface read and write failures. Preserve the existing JSON format or provide a tested migration.

**Acceptance.** Open a saved setlist with a drive disconnected, change another row, and restart. The unavailable rows stay in order and become playable after reconnecting or relinking. A corrupt snapshot or failed write produces a visible error and leaves recoverable data on disk.

## P1 — Make tag-edit results match what reached disk

**Implementation.** Tag edits are staged, reopened and verified per field before replacing the original. The editor reports saved fields and rejected values separately, and distinguishes a library-file write failure from an Apple Music refresh failure. A distinct ID3 work title is preserved. Legacy TIT1 is updated or removed only when absent or when it matches the existing grouping mirror. [Tag file writer](Sources/TangoDisplayTagging/TagFileWriter.swift) · [Tag editor](Sources/TangoDisplay/Services/TagEditor.swift)

**Finding.** The TagLib bridge discards unsupported properties returned by `setProperties` and reports success based on `save()`. The Music refresh path also discards AppleScript errors after writing the files. The current TagLib checks cover AIFF and M4A, while the editor offers MP3, WAV, FLAC, and Opus as well. [TagLib bridge](Sources/TangoDisplayObjC/TDTagWriter.mm#L39) · [Tag editing service](Sources/TangoDisplay/Services/TagEditor.swift#L15) · [Round-trip tests](Tests/TangoDisplayTests/TagWriterTests.swift#L9)

**Change.** Return per-field results for requested edits and warn when the file was updated but the Music library refresh failed. Define how new grouping values interact with existing `WORK`/`TIT1` values, since the compatibility mapping can overwrite or erase that frame. Round-trip the supported fields and clears through the same AVFoundation metadata reader used by the setlist.

**Acceptance.** Small fixtures cover every advertised format, unsupported fields, clearing values, and retention of unrelated tags. Failed replacement preserves the original file. If the local write succeeds and the Music-side operation fails, the dialog shows which operation needs attention.

**Verification.** The suite includes fixtures for all advertised formats, shared setlist-reader round trips, a distinct work-title case, and a simulated file replacement failure. The native fixture suite and Apple Music refresh still need execution with resolved dependencies and a desktop session respectively. [Tag writer tests](Tests/TangoDisplayTests/TagWriterTests.swift)

## P1 — Verify builds and packages before installation

**Implementation.** GitHub Actions runs the pinned build, tests and universal package smoke checks on Apple Silicon and Intel. The installer stages a copy on the destination volume, verifies it and restores the previous bundle if replacement fails. Build-only mode writes under `.build/package`. [macOS workflow](.github/workflows/macos.yml) · [Package smoke checks](Scripts/SmokePackage.sh)

**Finding.** The build instructions still say 39 tests and describe three targets with no external dependencies. The installer suppresses signing failures and then removes the destination app before copying the new bundle, so a failed copy can leave the old installation missing. [Build instructions](README.md#building-and-testing) · [Manifest](Package.swift) · [Signing and installation](Install.sh#L120)

**Change.** Document the checked-in dependency lock, supported toolchain, and normal build and test commands. Add macOS CI for `swift build` and `swift run TangoDisplayTests` using the lockfile. Give the packaging script a build-only mode and a configurable destination. Stage the bundle, verify resources, architecture slices and signatures, then replace the installed app with rollback on failure. Set up this verification alongside the playback and persistence fixes.

**Acceptance.** A fresh macOS checkout resolves pinned dependencies and runs the standard suite. Packaging can create and validate a bundle under `.build` without touching `/Applications`. Simulated signing or copy failure leaves an existing installation usable. Before release, smoke-test the bundle on macOS 13 and a current macOS version, including built-in playback, a cortina transition, a setlist restart, and an external presentation window. Exercise the Intel restoration path on an Intel runner or under Rosetta where available.

**Verification.** A locally signed universal fixture passed ZIP extraction, architecture, resource, signature and execution checks. Simulated copy, invalid-signature and replacement failures preserved the previous installation. The first hosted workflow run with the real bundle and the macOS 13 and external-display checks are pending. [Release smoke checklist](README.md#building-and-testing)
