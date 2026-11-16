# Troubleshooting

[Back to the README](../README.md) · [User guide](USER-GUIDE.md) · [Open an issue](https://github.com/bggg-gizmo/simple-pyrate/issues/new)

| Symptom | What to check |
| --- | --- |
| The app does not open | Extract the full ZIP and run `Start-Simple-Pyrate.cmd` beside the other scripts. Use Windows PowerShell 5.1 and .NET Framework 4.8. To see startup errors, run the diagnostic command below from the extracted folder. |
| The startup error names `IQueryAmbient` or `System.Xaml` | Extract the latest ZIP into a fresh folder. v2.5.3 retains the System.Xaml fix introduced in v2.5.1. |
| Shipyard says tools are missing | Open **Shipyard** and inspect the four paths. The app checks the **machine** PATH, not a user PATH, alias, or virtual environment. FFmpeg and FFprobe must come from the same folder. Select **Install missing tools** and approve Windows’ prompt. |
| Setup cannot download or verify an asset | Check the text in the setup window before pressing Enter. Proxies or firewalls may block GitHub or its release download redirects. A missing digest, incorrect download size, or hash mismatch stops installation of that package. Retry later or install the named dependency independently on the machine PATH. |
| Tools are found, but the terminal cannot find them | Reopen the terminal. Simple Pyrate reads the machine PATH directly, while an existing terminal may still have an older environment. |
| YouTube says a JavaScript runtime or challenge solver is missing | Start with current yt-dlp and Deno. If Shipyard installed them, try **Refresh managed tools**. If you installed them separately, update them with your package manager. See the [yt-dlp JavaScript setup guide](https://github.com/yt-dlp/yt-dlp/wiki/EJS) if you use a custom yt-dlp build. |
| A playlist or channel saves only one item | Select **Playlist / full channel** before clicking **Queue haul**. Use the channel’s main URL instead of a single post or channel-tab URL. Some sites do not allow yt-dlp to enumerate the account. |
| A file is missing or an entry says **Partial** | Open **Ship’s log** to see which item or format failed. Check available disk space and that the destination is writable. Confirm the video plays at the source and the type is supported. Then try **Retry selected**. |
| **No captions** appears | Confirm the source has captions for the selected language, or try `all`. If applicable, enable automatic captions and try again. No captions are created from speech. |
| The source says unavailable, requires sign-in, or is rate limited | Open the source link to verify it’s available. This app does not import credentials. Leave source-imposed waits alone and retry later if needed. |
| The boat is still at sea after the last file is saved | Check the queue row. If it shows a final result and no jobs remain, the animation may be catching up. Turn off **Motion** to skip visual transitions. If the row is still active, check **The deck** and **Ship’s log** instead. |

## See startup errors

Run this from Command Prompt in the extracted app folder:

```cmd
Start-Simple-Pyrate.cmd -Diagnose
```

For a noninteractive startup check that does not install tools or download media, run `Start-Simple-Pyrate.cmd -SmokeTest`. If startup fails, the diagnostic gives the stage and writes `%LOCALAPPDATA%\BGGG\Blackwake\startup-error.log` when available.

## Report a reproducible problem

Include your Windows version and architecture, the launch or failing action, the selected format and scope, and the relevant text from **Ship’s log** or the Shipyard window. Include a public example link if it is safe to share. Remove personal paths, private URLs, and access tokens from diagnostic output.


## Processing takes a long time

Check **The deck** before restarting. **Joining video and audio streams** is distinct from **MP4 audio encode** and **MP4 video encode**. Elapsed time updates even when FFmpeg cannot estimate the remaining time. When a conversion reports progress, speed and ETA come from FFmpeg. A compatible source is remuxed without recompressing. If a particular link still stalls, copy the ship’s log during the attempt and note the source link, operation, selected resolution, and whether Stop active works. A failed conversion leaves the original media in the Video folder.

If VLC plays the file but the queue remains active, note the exact status, file extension, and whether the file appears in **Saved files**. A playable file alone does not confirm that the job sent its completion event. Retest the same URL with v2.5.3 in a fresh save folder and capture the last lines of **Ship’s log** if it still happens.

If the wizard's tool setup fails, reopen it and retry after checking the network and UAC prompt. An elevated standard-user setup can write its log to the administrator account's profile. When troubleshooting that configuration, use the visible **Shipyard** install button to read the error in the console.
