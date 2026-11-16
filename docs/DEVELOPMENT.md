# Development and verification

[Back to the README](../README.md) · [Changelog](../CHANGELOG.md)

## Source layout

| Path | Purpose |
| --- | --- |
| [`Start-Simple-Pyrate.cmd`](../Start-Simple-Pyrate.cmd) | Starts Windows PowerShell 5.1 in STA mode. |
| [`SimplePyrate.ps1`](../SimplePyrate.ps1) and [`assets/Deck.xaml`](../assets/Deck.xaml) | WPF window, queue, dialogs, settings, and download telemetry. |
| [`Engine.ps1`](../Engine.ps1) | yt-dlp invocation, queue events, cancellation, and transcript export. |
| [`Install-Tools.ps1`](../Install-Tools.ps1) | Elevated dependency installation and machine PATH registration. |
| [`VoyageTimeline.cs`](../VoyageTimeline.cs), [`VoyageCanvas.cs`](../VoyageCanvas.cs), and [`RaidCanvas.cs`](../RaidCanvas.cs) | State transitions, event-driven scene rendering, and raid milestones. |
| [`Shipwright.ps1`](../Shipwright.ps1), [`assets/audio/`](../assets/audio/), and [`assets/build-audio.py`](../assets/build-audio.py) | Settings, setup wizard, offline soundtrack, and sound-effect assets and generator. |
| [`assets/voyage`](../assets/voyage/) and [`assets/Night-Sea.wav`](../assets/Night-Sea.wav) | Bundled original scene layers and ambience. |
| [`assets/build-voyage.py`](../assets/build-voyage.py) and [`assets/make-sea.py`](../assets/make-sea.py) | Rebuild the scene layers with Python 3 and Inkscape, and the audio with Python 3. Neither script is needed at runtime. |
| [`tests/`](../tests/) | Engine, voyage, and upgrade checks and local media fixture. The archived suites are under [`old_builds/`](../old_builds/). |

The original `Blackwake.ps1` and `Start-Blackwake.cmd` filenames are compatibility entry points. Preserve the existing settings and managed tools paths when changing branding or packaging.

## Run the checks locally

From Windows Command Prompt at the repository root:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\Engine.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\Voyage.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\tests\Upgrade.Tests.ps1"
Start-Simple-Pyrate.cmd -SmokeTest
```

The WPF smoke test opens the native window and checks that the rendered scene has real pixel content, then checks progress, caption controls, and the narrow layout. In v2.5.2 it also constructs Settings and the Shipyard wizard and checks the raid threshold and audio files. It exits with code 0 on pass or 1 on a startup or test failure. It does not install dependencies or download media. Run it on Windows separately from the cross-platform tests.

For a real download test without using a social platform, install Python 3, yt-dlp, and FFmpeg, then start the local test server in one terminal:

```cmd
python tests\local_fixture.py
```

Run this in a second terminal from the repository root:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\tests\Engine.Tests.ps1' -YtDlp (Get-Command yt-dlp.exe).Source -Ffmpeg (Get-Command ffmpeg.exe).Source -FixtureUrl 'http://127.0.0.1:8769/index.html' -CollectionUrl 'http://127.0.0.1:8769/collection.html'"
```

The integration checks exercise MP4, MP3, TXT and SRT outputs, missing captions, ordered collection encounters, source-wait events, and cancellation. The test server binds to loopback and serves generated clips and captions.

## v2.5 audit results

The Windows ZIP and its 24 files matched the repository’s original upload byte for byte. All 45 engine checks and 20 timeline checks passed under PowerShell 7.4.19 on Linux, with yt-dlp 2026.10.26 and FFmpeg serving and processing local fixtures. All PowerShell scripts parsed, the XAML names matched all 58 code-behind bindings, and the two C# renderer files compiled as C# 5 against .NET Framework 4.8 WPF references.

The native Windows smoke test, UAC and machine-PATH setup on Windows, and live social-platform extraction were not run in that audit. A compile or a local fixture pass does not establish Windows end-to-end behavior.

## v2.5.1 startup verification

On a Windows PowerShell 5.1 installation, v2.5 failed when its native compiler tried to resolve the renderer’s inherited `IQueryAmbient` interface without a reference to `System.Xaml`. v2.5.1 explicitly loads that assembly and passes it to the compiler. The launcher also accepts `-SmokeTest` and `-Diagnose`, preserving the PowerShell exit code for both modes.

The v2.5.1 renderer sources compiled with the launcher’s explicit references against Microsoft .NET Framework 4.8 targeting assemblies and the x64 Windows runtime assemblies. A small compile probe verified that the interface fails to resolve without `System.Xaml` and resolves with it. The 45 engine and 20 voyage checks were rerun. This is not a native Windows run. Run the CMD smoke test on Windows before public distribution.

## Before distributing another build

1. Run the engine, voyage, and upgrade tests, then the native WPF smoke test on Windows.
2. On a test PC or VM, launch as a regular user. Check first-run Shipyard, UAC, the machine PATH, and restart behavior. If both Windows architectures are being advertised as verified, test both x64 and ARM64.
3. Try one permitted real-world media URL and one collection with captions. Record the source and yt-dlp version. The local fixture does not establish live platform compatibility.
4. Stage the launcher, scripts, C# files, assets, and tests together. Preserve CRLF and the UTF-8 BOM on the Windows PowerShell scripts.
5. Extract the finished ZIP into a clean folder and run its launcher and smoke test from that folder. Calculate its SHA-256 and update `SHA256SUMS.txt` with the exact archive name.

## Verify a Windows ZIP

```powershell
Get-FileHash .\Simple-Pyrate-v2.5.2-Windows.zip -Algorithm SHA256
```

Compare the result with the [expected checksum](../SHA256SUMS.txt) generated from the packaged build. The checksum is intentionally stored outside the ZIP. The v2.5.2 ZIP contains the current source, assets, documentation, tests, and unchanged archived sources. Repository documentation may be updated independently of the downloadable archive.


## v2.5.2 verification

The engine emits a port and transfer lifecycle independently of WPF. The voyage timeline owns threshold ordering and never waits on audio or rendering. The queue owns finalization and reported output files. The separate FFmpeg process provides conversion telemetry and uses the same cancellation path as yt-dlp. The themed setup dialogs remain in the existing non-elevated deck process. Only the existing dependency worker elevates.

Run `tests/Upgrade.Tests.ps1` for pure progress and raid tests. With FFmpeg and ffprobe from the same installation, pass `-Ffmpeg` with the executable path to exercise real remux and both encode paths. To include the real yt-dlp handoff, also pass `-YtDlp` and `-FixtureBase http://127.0.0.1:8769` while `tests/local_fixture.py` is running. Use the [Windows checklist](WINDOWS-TEST.md) for startup and human testing. The archived tests under `old_builds/` are historical, not the current verification target.
