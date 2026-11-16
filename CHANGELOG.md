# Changelog

## v2.5.2

- Added four original pirate MIDI scores, offline playback in three playlists, a track skip control, and separate music and port-effects volume. The sea ambience and Motion switches still work independently.
- Added six per-item port raid beats at 30%, 50%, 75%, 80%, 95% and 98%. The harbor catches fire, dinghies carry the crew ashore, crates move aboard, and the ship recovers the crew and dinghies. New synthesized sound effects follow the scenes.
- MP4 finalization now keeps ready MP4s intact, prefers stream-copy remuxing for compatible inputs, and shows actual FFmpeg progress when conversion is needed. Original media stays on disk on failure or cancellation.
- Added the Captain’s settings donation link for Monero, including a selectable XMR address and clipboard fallback.
- Added the themed first-run Shipyard wizard with portable and per-user app options, download-folder selection, shortcut setup, dependency inspection, and retry after failed or declined installation. System-wide tool installation still requires UAC.
- Kept the Windows PowerShell 5.1 System.Xaml fix, the CMD diagnostic flags, and the archived `old_builds/` files. Expanded the smoke test, local fixtures, and manual Windows checklist.

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
