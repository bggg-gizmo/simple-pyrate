# Changelog

## v2.6.3

- Add session-only use of a selected signed-in Windows browser through yt-dlp. Preserve manual cookies.txt and PO token options.
- Show live resolve steps in the active haul and log time to the first source metadata.
- Put a shortcut to the existing Monero donation controls near the top of Settings.
- Preserve the launcher, installer, architecture-specific runtimes, visuals, audio, and queue.

### Android

- Put the existing XMR donation address and wallet actions one tap from the top of Settings.
- Add opt-in Android Keystore protection for remembered source access and one-tap reuse from the deck. Keep the original session-only option and manual inputs.
- Prepare the bundled runtime off the UI thread when the deck opens. Allow yt-dlp to reuse its app-private extractor cache and show live resolve steps.

## v2.6.2

- Keep Download, output formats, PO token access, and progress on the first screen. Move advanced download options and queue management into their own panels without removing their controls.
- Give the original animated ship and port their own unobstructed viewport in portrait and landscape. Put the voyage caption in a separate band and preserve the original art, movement, sound effects, and audio controls.
- Pass the PO token and its matching player client through private job configuration. Keep credentials session-only.
- Reuse one Python process and successful source metadata for multi-format single-link hauls. Record source, transfer-start, and finalizing/saving timings in the ship’s log.
- Add a host regression test for extraction reuse and token parsing and an Android layout smoke check.

## v2.6.1

- Use the supplied gold pirate ship as the app icon, with adaptive and legacy Android resources and a dark background.
- Build directly with javac and D8 using the manifest minimum API. Package every DEX and the two native runtime sets, align before signing, and verify the final APK.
- Keep the original Android runtime, voyage scenes, sound, and download features unchanged.

## v2.6.0

- Add a standalone portrait-first Android APK with rotating layouts, a background voyage, full haul controls, and the original Windows ship, ports, music, and effects.
- Include the Python, QuickJS, FFmpeg, FFprobe and yt-dlp toolchain on Android. Shipyard can update yt-dlp against the upstream release SHA-256. Native runtime updates use a signed APK.
- Windows now falls back to bundled x64 or ARM64 yt-dlp, Deno, FFmpeg and FFprobe. The optional machine-PATH updater still verifies packages before installing or refreshing them.
- Add session-only Source access on both platforms for user-provided cookie exports and optional YouTube PO tokens.
- Preserve the accepted Windows rendering, audio, settings, download completion, and installer workflow.

## v2.5.7

- Accepted by the maintainer after testing. The reported silence was traced to the saved Port sound effects setting being off, not to missing recordings. New profiles default to on. Upgrades retain the saved choice.
- Keep one forward-facing ship position across the sailing and port shots. Slide the departing coast left and approach the next port from the right. The return still plays only after the final port or a cancellation.
- Mix the existing WAV effects, bells and ambience in one Windows output stream, including when the sea loop is active. Run device work off the UI thread, preserve the individual audio controls, and report failures per recording.
- Play port cues even with Motion off, and add a two-port camera regression test and a concurrent audio test. Keep v2.5.6 in `old_builds/v2.5.6/`. No new audio libraries or assets.

## v2.5.6

- Restore the v2.5.4 deck animation, original ship staging and raid visuals, and the previous frame cadence. Remove the extra scene compositing from v2.5.5.
- Play the existing WAV port effects, ship bells, and sea loop through Windows PCM audio. Preserve the existing playlists, switches, volume controls, and recordings. Report device errors in **Ship’s log**.
- Exclude historical builds from the current source ZIP while keeping them in the repository. Preserve v2.5.5 under `old_builds/v2.5.5/`.
- Add a startup smoke check for the format of every bundled WAV. Native listening and rendering checks are pending.

## v2.5.5

- Synchronize visual updates with WPF rendering and dissolve between consecutive voyage shots. Keep the active battle title readable through longer transfers.
- Ease dinghies, crew, cargo, fires, and the final port damage between milestone poses. An incoming batch cannot shorten the animation that is already playing. Keep all six original thresholds and the Motion-off behavior.
- Play each port sound with its own voice so the next cue no longer stops the previous one. Keep the existing recordings, volumes, playlists, ambience, and three/two/five ship-bell patterns. Port effects are enabled for a new profile and existing preferences are preserved.
- Keep the previous build under `old_builds/v2.5.4/`. Native Windows rendering and listening checks are pending.

## v2.5.4

- Restore the original ship rendering on the Shipyard welcome page, including the original camera framing, water, wake, fog, and shading. The welcome title and subtitle stay outside the artwork.
- Keep the deck cinematics, port milestones, music, sound effects, ship bells, and settings unchanged.
- Extend the Windows smoke test to render the Shipyard ship artwork at three widths. Native Windows verification is pending.
- Preserve the previous source and assets under `old_builds/v2.5.3/`.

## v2.5.3

Windows test candidate. Follow the [Windows verification checklist](docs/WINDOWS-TEST.md) before treating this build as verified.

- Use a shared release version for the deck, launcher checks, setup installer, and diagnostics. Keep old per-user install folders and preferences intact.
- Keep the corrected **Welcome to Simple Pyrate** and **Let’s set up your ship** first-run wizard, with themed artwork separate from its text. Retain the original controls, formats, music, raid milestones, and ship bells.
- Stop waiting indefinitely on a quiet inherited output pipe after the downloader has already exited. Process any output available on either stream first and keep the downloader’s real exit code. Add a regression covering that handoff.
- Preserve the previous source and original Windows ZIP under `old_builds/v2.5.2/`.

## v2.5.2

### Setup and ship-bell update

- Aligned the four setup pages, made dependency names and paths separate columns, and kept navigation buttons level. The current launcher offers the corrected wizard once for users who completed the older one. A per-user upgrade keeps the previous app folder and updates shortcuts that point to that known install.

- The first-run wizard welcomes users to Simple Pyrate and presents its setup text separately from the artwork. The idle deck now gives a direct download prompt.
- Added a resonant ship bell with three strikes at departure, two per batch port, and five when the queue finishes. The existing **Port sound effects** setting and volume apply. The queues and transfers do not wait for audio.
- Added regression checks for the welcome layout, bell recordings, and cue timing. The current repository source ZIP includes this update. The original Windows ZIP and its checksum are unchanged.

### Original package

- Added four original pirate MIDI scores, offline playback in three playlists, a track skip control, and separate music and port-effects volume. The sea ambience and Motion switches still work independently.
- Added six per-item port raid beats at 30%, 50%, 75%, 80%, 95% and 98%. The harbor catches fire, dinghies carry the crew ashore, crates move aboard, and the ship recovers the crew and dinghies. New synthesized sound effects follow the scenes.
- MP4 finalization now keeps ready MP4s intact, prefers stream-copy remuxing for compatible inputs, and shows actual FFmpeg progress when conversion is needed. Original media stays on disk on failure or cancellation.
- Added the Captain’s settings donation link for Monero, including a selectable XMR address and clipboard fallback.
- Added the themed first-run Shipyard wizard with portable and per-user app options, download-folder selection, shortcut setup, dependency inspection, and retry after failed or declined installation. System-wide tool installation still requires UAC.
- Kept the Windows PowerShell 5.1 System.Xaml fix and CMD diagnostic flags. Expanded the smoke test, local fixtures, and manual Windows checklist.
- Published the [Windows ZIP](old_builds/v2.5.2/Simple-Pyrate-v2.5.2-Windows.zip) on `main` with its [expected SHA-256](SHA256SUMS.txt). Preserved v2.5.1 at [`old_builds/v2.5.1/`](old_builds/v2.5.1/) and the earlier [v2.5 archive](old_builds/README.md).
- The packaged build passed 113 local checks. See the [audit](docs/V2.5.2-AUDIT.md) and [Windows checklist](docs/WINDOWS-TEST.md) for what was tested and what remains.

## v2.5.1

- Fixed Windows PowerShell 5.1 startup by explicitly referencing System.Xaml when compiling the WPF voyage renderer.
- Added `-SmokeTest` and `-Diagnose` to the CMD launcher and preserved the exit code. Startup errors now name the failed stage and, when available, write a local log.
- Added a new v2.5.1 archive and checksum. The v2.5 archive is retained for version history.

## v2.5

- Windows launcher and dark-only WPF desktop interface under the Simple Pyrate name.
- Single items and full playlists or channels, with queue controls for stopping, removing, retrying, and clearing finished jobs.
- MP4, MP3, and transcript exports. Transcript-only jobs can write TXT, SRT, or both without saving media.
- Moonlit lagoon, departure, source-wait sailing, per-item port encounters, and return cutscenes. Motion and sea ambience are separately configurable.
- Shipyard detects dependencies on the system PATH and verifies downloaded release assets before installing missing tools.
- Legacy Blackwake launchers, settings, and managed tools remain compatible.

## Repository documentation

- Added a visual README, original-art banner, local SVG badges, and labeled UI previews.
- Added a user guide, troubleshooting, local verification instructions, and a SHA-256 checksum for the existing Windows ZIP.
