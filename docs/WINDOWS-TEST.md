# Windows release-candidate checklist

Run this on Windows 10 or 11 in an interactive desktop session. Do not test v2.5.2 by copying it over v2.5.1. Extract the complete package to its own folder. Current scripts are in the root of the app, not in `old_builds`.

## 1. Prove Windows PowerShell 5.1 startup first

In Command Prompt, change to the extracted root and run:

```cmd
Start-Simple-Pyrate.cmd -SmokeTest
echo %errorlevel%
```

Expected result is the v2.5.2 WPF smoke test pass message and exit code `0`. This exercises the same Windows PowerShell 5.1 compiler and assemblies as the normal launcher, loads WPF XAML, renders the 98% port scene, constructs the settings and setup screens, and checks the new audio files are present. It does not install anything, open a wallet, change preferences, or play audio.

If it fails, preserve the exact console output and `%LOCALAPPDATA%\BGGG\Blackwake\startup-error.log`. If the normal launch fails, run `Start-Simple-Pyrate.cmd -Diagnose` for console output. Report Windows build, processor architecture, and the startup stage from the log.

## 2. Check Shipyard and install paths

1. Run `Start-Simple-Pyrate.cmd -Setup`. Check Back, Next, Later, invalid folder handling and **Browse folders**.
2. With tools already on the machine PATH, confirm the inspection shows their paths and skips UAC. Finish in portable mode, reopen the app, and confirm the destination persists.
3. In a clean Windows account or disposable VM with missing system tools, reach **Install missing tools**, decline UAC once, and confirm the wizard offers a retry. Retry and approve. Confirm that tools are visible under the system PATH and only the tool worker elevates.
4. Select **Install an app copy for this Windows account** and optionally **Create a Desktop shortcut**. Finish. Launch the versioned Start Menu entry and confirm it starts from `%LOCALAPPDATA%\BGGG\Simple Pyrate\App-2.5.2`. Do not remove the extracted folder if your shortcut points to a portable copy.
5. After an install, verify the original save folder and existing files were not modified. If you used v2.5.1 first, confirm your previous save, Motion, and sea sound choices carry over. A missing download folder is created only when the wizard finishes or a haul needs it.

## 3. Exercise the haul and sounds

- In **Settings**, start each playlist, skip a track, adjust music volume, and verify it still loops after the dialog closes. Test port sound preview with SFX enabled. Toggle sea sound separately. Mute all three and verify silence.
- Try a single MP4, an MP3, a transcript-only haul, and a small collection with all three outputs. Check the saved-file browser, session log, stop, retry, and existing-file behavior. Try a source without captions.
- Watch the independent port milestones at 30%, 50%, 75%, 80%, 95%, and 98%. A small item should play the reached milestones in order before the next encounter. Toggle Motion off and check the still version and immediate return after completion.
- Observe a source already in MP4 and a WebM source that goes through the finalizer. The deck should name the merge or encode operation, track elapsed time, and show real percentage or an indeterminate bar when duration is unavailable. During a longer conversion, try **Stop active**. Confirm the source intermediate is preserved, no incomplete MP4 is reported as finished, and restarting does not overwrite a finished MP4.
- Copy the XMR address from **Settings** and compare it with the displayed address. If you have a registered Monero wallet, open the URI and verify its recipient. Do not send a payment as part of testing.

The candidate was exercised with Linux PowerShell 7, the local HTTP fixtures, real yt-dlp, and real FFmpeg. The renderer was compiled using Microsoft .NET Framework 4.8 targeting and x64 runtime assemblies with the launcher's reference list. Neither check substitutes for this Windows run, native audio playback, a live site test, or actual administrator approval.
