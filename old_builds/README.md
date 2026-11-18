# Simple Pyrate v2.5

**A moonlit Windows chart room for video, audio and transcripts.**

Developed by **The Background Gremlin Group**  
Developing unique tools for unique individuals · **BGGG / Est. 2020**

## Launch on Windows

1. Extract the entire ZIP to a folder you control. Keep the scripts and the assets folder together.
2. Double-click **Start-Simple-Pyrate.cmd**. It opens the desktop window using Windows PowerShell 5.1 in STA mode. Windows needs .NET Framework 4.8 (included with Windows 11 and Windows 10 22H2). No Python, virtual environment, Node.js, browser or .NET SDK is needed to launch it.
3. On first launch, choose **Install missing tools** if Shipyard reports any missing. Approve Windows’ administrator prompt. The separate setup window closes when it succeeds.
4. Paste one complete link per line. Choose **Single item per link** or **Playlist / full channel**, pick the formats, and click **Queue haul** or press **Ctrl+Enter**.

The app is shipped as full source with a CMD launcher, not as a compiled EXE. It targets 64-bit Windows 10 and 11 (x64 and ARM64). The launcher uses a process-only PowerShell execution-policy override. It does not change Windows’ machine or user execution policy or bypass a system administrator’s Group Policy.

## Choose what to save

| Choice | What you get | Folder |
| --- | --- | --- |
| MP4 | Video with audio when present. Video quality can be capped from 480p to 2160p. | `Video` |
| MP3 | Audio only. Choose 128, 192, 320 kbps, or the best variable bitrate. | `Audio` |
| Transcript → TXT | Plain text from a caption track, with timings and styling removed. No media or SRT is retained in this mode. | `Transcripts` |
| Transcript → SRT | Timed subtitle files. No media is downloaded if Transcript is the only mode selected. | `Transcripts` |
| Transcript → Both | TXT and SRT from the same matching tracks. | `Transcripts` |

Check any combination. Each URL is one queue entry, with a separate pass for each selected output. Paste a YouTube channel’s main URL in **Playlist / full channel** mode for the uploads yt-dlp can enumerate, including Shorts and streamed uploads where available. A `/videos`, `/shorts` or `/streams` URL restricts a YouTube haul to that tab. A playlist link without collection mode processes only its first entry. Some extractors accept posts or individual videos but cannot enumerate a whole profile. For an unsupported profile, paste the direct links you want in the batch.

The fresh-install default location is `%USERPROFILE%\Downloads\Simple Pyrate`. **Browse** lets you enter a new path, navigate folders, or choose another drive. **Saved files** lists available files from this session, including valid finished files found in the destination on retries. Double-click a file to open it. Your selections and destination are remembered. The queue, saved-file list, and ship’s log are session-only.

Use **Stop active** to stop the current haul, **Remove selected** for a queued entry, and **Retry selected** for a failed, stopped, or partial entry. Finished files are retained and existing outputs are not overwritten. An interrupted media download can leave a part file for yt-dlp to resume when the source supports it. **Clear finished** clears rows, not files. **Motion** controls the cinematic scenes, animated backdrop, and progress sweep. **Sea sound** plays the bundled local ambience and is off by default.

## The voyage

- **At anchor.** The ship rocks under the moon in the lagoon until a haul starts.
- **Setting sail.** Ghostly titles drift through fog while the ship leaves the cove. The next cut is open water. If yt-dlp reports a wait, the open-water shot shows the remaining time. Simple Pyrate does not impose a blanket three-second delay.
- **Plundering in progress.** Each resolved video, audio, or transcript item is its own numbered port encounter. Four fictional port silhouettes rotate as the coastline changes. While an encounter is active, the ship fires animated salvos, with muzzle light, flying sparks, and drifting smoke. An item that has no matching subtitles still gets an encounter, and the queue reports that no file was saved.
- **On to the next port.** Successive items or queued links stay on one voyage. Each battle is separated by an open-water shot. Very fast items can finish before their scenes play, so the cutscenes can briefly catch up after the download queue is done. They never hold up downloading, file saving, or the queue.
- **Making for harbor.** After the last encounter, the ship sails back into the lagoon. Cancelling the last job skips the pending visual encounters and turns the ship for harbor immediately. Turning off Motion removes the animated transitions and decorative effects.

## Captions and sites

Simple Pyrate uses yt-dlp’s extractors for YouTube, Rumble, TikTok, Instagram, X and other supported sites. Support depends on the exact URL and what the site serves. This release does not import browser sessions, ask for credentials, or attempt to bypass access restrictions or DRM. Private or sign-in-only posts may fail, and some public profiles require authentication or do not expose an upload list.

The language field accepts codes such as `en`, `de`, `pt-BR`, or comma-separated combinations. A base language can match regional tracks. Use `all` alone for every exposed caption language except live chat. Manually supplied subtitles take precedence over automatic captions for the same language. Automatic captions are optional and only work where the source exposes them. Simple Pyrate does not generate new captions from speech. When a source publishes no matching convertible track, the app reports that in the queue and log.

## What Shipyard changes

- Checks for `yt-dlp.exe`, `ffmpeg.exe`, `ffprobe.exe` and `deno.exe` on the **Windows system PATH**, not the current user’s PATH or a virtual environment. FFmpeg and FFprobe must be in the same PATH directory.
- Installs missing tools under `%ProgramFiles%\BGGG\Blackwake\bin`, verifies the downloaded release asset against its published SHA-256 and byte count, then adds the directory to the machine PATH in the Windows registry. App sessions read the updated machine PATH directly. An already-open terminal may need to be reopened.
- Reuses existing tools on the machine PATH. **Refresh managed tools** updates managed packages and leaves unrelated copies untouched. Simple Pyrate runs its job worker without requesting elevation. Run the app normally and let Windows elevate only Shipyard.
- Upstream builds come from [yt-dlp](https://github.com/yt-dlp/yt-dlp/releases), [BtbN FFmpeg Builds](https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases) and [Deno](https://github.com/denoland/deno/releases). Existing Deno installations should be at least 2.3. Existing yt-dlp executables should be current.
- If you want to remove just Simple Pyrate, delete its extracted folder. The existing settings path, `%LOCALAPPDATA%\BGGG\Blackwake`, is preserved so an update picks up your preferred save folder and other options. The managed Program Files directory is also reused. To remove its managed tools as well, remove only the existing Blackwake bin entry from **System Properties → Advanced → Environment Variables → System variables → Path** and delete `%ProgramFiles%\BGGG\Blackwake` as an administrator. This does not touch your downloads or tools installed by other apps.

## Verification

On Windows, check the native interface and progress control from Command Prompt:

```cmd
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\SimplePyrate.ps1" -SmokeTest
```

Run the engine and voyage timeline checks:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\Engine.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\Voyage.Tests.ps1"
```

If Python and FFmpeg are available for development, start the bundled local fixture server with `python tests\local_fixture.py`. Then run this in a separate Command Prompt after installing or locating yt-dlp and FFmpeg on the PATH:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\tests\Engine.Tests.ps1' -YtDlp (Get-Command yt-dlp.exe).Source -Ffmpeg (Get-Command ffmpeg.exe).Source -FixtureUrl 'http://127.0.0.1:8769/index.html' -CollectionUrl 'http://127.0.0.1:8769/collection.html'"
```

The 65 checks cover output formats, single and multi-item downloads, item-to-port events, source waits, return timing, cancellation and reduced motion. The engine and timeline tests ran under PowerShell 7 on Linux using real yt-dlp and FFmpeg with the bundled local HTTP fixture. The C# renderer compiled against .NET Framework 4.8 WPF reference assemblies. The native Windows GUI, UAC/machine-PATH changes and live social-media extraction were not run here.

## Project files

| File | Purpose |
| --- | --- |
| `Start-Simple-Pyrate.cmd` | Windows launcher |
| `Start-Blackwake.cmd` and `Blackwake.ps1` | Compatibility entry points for the earlier name |
| `SimplePyrate.ps1` | Desktop interface, queue manager, output browser and log |
| `VoyageTimeline.cs` | Predictable scene state machine, independent of the download worker |
| `VoyageCanvas.cs` | Native WPF camera, water, fog, titles, and fictional cannon effects |
| `Engine.ps1` | Tool discovery, argument handling, jobs, events and caption export |
| `Install-Tools.ps1` | Elevated dependency setup and registry PATH registration |
| `assets/Deck.xaml` | Dark WPF interface and fixed cinematic backdrop |
| `assets/voyage/*.png` | Original layered ship, port, fog, and night-sky artwork |
| `assets/build-voyage.py` | Rebuilds the voyage layers with Python 3 and Inkscape (not required to run the app) |
| `assets/Night-Sea.wav` | Original synthesized sea ambience |
| `assets/make-sea.py` | Source that regenerates the audio asset |
| `tests/Engine.Tests.ps1` | Unit checks and optional real download integration tests |
| `tests/Voyage.Tests.ps1` | Deterministic timeline and playback checks |
| `tests/local_fixture.py` | Local media and caption fixtures for testing |

[bggg] The Background Gremlin Group • Est. 2020

## v2.5.7

[Windows source snapshot](v2.5.7/) from the last v2.5.7 commit on `main`, including the animated walkthrough. This preserves the accepted build as it existed before v2.6.3.
