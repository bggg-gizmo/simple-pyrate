# Simple Pyrate 2.6.3 for Android

Developed by **The Background Gremlin Group**  
Developing unique tools for unique individuals · **BGGG / Est. 2020**

Simple Pyrate runs on Android 10 and newer on 64-bit ARM and x86-64. The installed app includes all media dependencies and needs no Termux, SDK, Gradle, separate Python, or separate FFmpeg install. APK installation uses Android's normal package installer. See [Android installation](docs/ANDROID-INSTALL.md).

## First haul

1. Open Simple Pyrate. Shipyard welcomes you and lets you choose a save location, check the bundled tools, and finish setup.
2. Paste one complete HTTP or HTTPS media URL per line. Choose **Single item per link** or **Whole playlist or channel**. Collection support depends on what the source exposes.
3. Choose one or more of **MP4**, **MP3**, and **Transcript**. Settings include video resolution, MP3 quality, caption language, automatic captions, and TXT, SRT or both.
4. Tap **Download**. The voyage stays visible in a clear area of the animated background, with progress beside the controls. Tap **Queue → Saved files** or browse **Downloads / Simple Pyrate** for the exported files. A picked folder uses the Android system folder grant.
5. If a supported site requires your authorized session, tap **PO token** on the main deck or open **Settings → Source access**. A cookies.txt file must be in Netscape format. YouTube PO tokens use the yt-dlp client.context+token format. A PO token does not sign an account in or perform age verification. Use credentials only for an account you control. By default access is session-only. Choose **Remember on this device** to protect an imported cookie file and/or PO token with the Android Keystore. Next time tap **Use sign-in** on the deck to activate it. **Forget saved sign-in** deletes the saved copy. Android cannot reuse Chrome or YouTube sign-in directly. Expired credentials need a new export or token. Clearing them applies to future hauls. Remove existing queued jobs if you also want to discard their captured credentials.

Use **Options** for download scope, video and MP3 quality, caption language and format, and the save folder. **Queue** keeps the existing stop, retry, remove, log, and saved-file controls together. The ship and port are never overlaid by the voyage title.

MP4 files, MP3 files and transcripts go into the Video, Audio, and Transcripts folders respectively. The downloader runs with a foreground notification when Android allows it, and active work continues when you rotate the device. The queue, saved-file list and ship's log are session-only, while exported files remain. Android may suspend or stop long-running background work under its ordinary process and power limits.

For a single link with multiple requested formats, the app starts the bundled Python downloader once. It reuses successful video metadata within that haul when safe, while keeping per-format quality selection and export behavior. Live and collection jobs retain separate extraction. The ship’s log reports time to source metadata, time to first transfer, and time spent finalizing and saving. Those times depend on the source, network, and device.

The Android runtime prepares on a background thread as the deck opens. yt-dlp can reuse supported extractor data, including YouTube player-signature work, in its app-private cache. The resolve status distinguishes source pages, player requests, and manifests. The first lookup for a source or new player may still take time.

Open **Settings → Support the crew · XMR donation** to view or copy the existing donation address or open it in a Monero wallet.

## Sound and motion

The original ship, port silhouettes, layered moon and sea artwork, playlists, sea loop and recordings are used by the Android renderer. It plays departure, open water, the port volley and the crew's six raid milestones, and the final return. Batches keep forward motion between ports. Scene playback does not block downloads. Port SFX and ship bells are on for a new profile. Music and sea ambience are independent. The bell sequences are three starting strikes, two at each batch port and five at the end of a successful voyage. **Motion** disables decorative playback without disabling sound.

## Tool updates

**Shipyard → Update yt-dlp** fetches the official stable zipapp, compares its published GitHub SHA-256 and byte count, checks its version locally, and replaces the previous zipapp atomically. The bundled executable runtime and libraries remain in the signed Android package. Updating native Python, QuickJS, FFmpeg or FFprobe requires an APK update signed with the same key. An installation with another signing key cannot be updated in place by this build.

## Build directly

The complete Android source release ZIP includes the pinned runtime files and original icon artwork. In a Git checkout, restore those assets from the release archive by following the [runtime hydration guide](../docs/RUNTIME-HYDRATION.md).

The Android source archive includes Java source, manifest, resources, original assets, vendor payloads and source/license metadata. A source rebuild uses the supplied OpenJDK 17, extracted r36 build tools, the supplied `android-36/android.jar`, and your APK signing key. It follows MirrorMax’s direct Java 11, JAR and D8 sequence, with native libraries packaged and page-aligned before signing. End users do not install any of those build-time tools. There is no Gradle project, Android Studio project, CI, or GitHub Action.

Run from the extracted root with these arguments in order.

    ./build.sh "$JDK_DIR" "$BUILD_TOOLS_DIR" "$ANDROID_JAR" vendor/native "$KEYSTORE" "$KEY_ALIAS" Simple-Pyrate-2.6.3-Android.apk

Let apksigner prompt for the keystore password, or provide the path to a protected password file as PYRATE_KEYPASS_FILE. The private signing key is not in the source archive.

The optional test APK is never included in the release APK. See tests/README.md. Dependency licenses and source details are in THIRD_PARTY.md and licenses. The original Simple Pyrate code and assets retain the included BGGG MIT license.
