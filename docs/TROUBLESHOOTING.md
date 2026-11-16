# Troubleshooting

[Back to the README](../README.md) · [User guide](USER-GUIDE.md) · [Open an issue](https://github.com/bggg-gizmo/simple-pyrate/issues/new)

| Symptom | What to check |
| --- | --- |
| The app does not open | Extract the full ZIP and run `Start-Simple-Pyrate.cmd` beside the other scripts. Use Windows PowerShell 5.1 and .NET Framework 4.8. To see startup errors, run the diagnostic command below from the extracted folder. |
| Shipyard says tools are missing | Open **Shipyard** and inspect the four paths. The app checks the **machine** PATH, not a user PATH, alias, or virtual environment. FFmpeg and FFprobe must come from the same folder. Select **Install missing tools** and approve Windows’ prompt. |
| Setup cannot download or verify an asset | Check the text in the setup window before pressing Enter. Proxies or firewalls may block GitHub or its release download redirects. A missing digest, incorrect download size, or hash mismatch stops installation of that package. Retry later or install the named dependency independently on the machine PATH. |
| Tools are found, but the terminal cannot find them | Reopen the terminal. Simple Pyrate reads the machine PATH directly, while an existing terminal may still have an older environment. |
| YouTube says a JavaScript runtime or challenge solver is missing | Start with current yt-dlp and Deno. If Shipyard installed them, try **Refresh managed tools**. If you installed them separately, update them with your package manager. See the [yt-dlp JavaScript setup guide](https://github.com/yt-dlp/yt-dlp/wiki/EJS) if you use a custom yt-dlp build. |
| A playlist or channel saves only one item | Select **Playlist / full channel** before clicking **Queue haul**. Use the channel’s main URL instead of a single post or channel-tab URL. Some sites do not allow yt-dlp to enumerate the account. |
| A file is missing or an entry says **Partial** | Open **Ship’s log** to see which item or format failed. Check available disk space and that the destination is writable. Confirm the video plays at the source and the type is supported. Then try **Retry selected**. |
| **No captions** appears | Confirm the source has captions for the selected language, or try `all`. If applicable, enable automatic captions and try again. No captions are created from speech. |
| The source says unavailable, requires sign-in, or is rate limited | Open the source link to verify it’s available. This app does not import credentials. Leave source-imposed waits alone and retry later if needed. |
| The boat is still at sea after the last file is saved | The animation may be catching up with a fast transfer. Disk writes and queue processing are already done. Turn off **Motion** to skip visual transitions. |

## See startup errors

Run this from Command Prompt in the extracted app folder:

```cmd
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File ".\SimplePyrate.ps1"
```

## Report a reproducible problem

Include your Windows version and architecture, the launch or failing action, the selected format and scope, and the relevant text from **Ship’s log** or the Shipyard window. Include a public example link if it is safe to share. Remove personal paths, private URLs, and access tokens from diagnostic output.
