# Windows bundled tools

Keep the runtime directories alongside the rest of the extracted application. The first candidate is the Windows machine PATH, with copies managed by Shipyard preferred. If either FFmpeg or FFprobe is missing from a common machine directory, the app chooses the matching bundled pair. It never mixes DLLs across architectures.

The bundled files are from yt-dlp 2026.10.26, Deno 2.9.8, and BtbN FFmpeg 8.1 GPL shared x64 and ARM64 builds. The full upstream asset names, original byte sizes, URLs and SHA-256 digests are recorded in release-assets.json. Those digests apply to the original upstream archives and executables.

Dependencies are independent executables with their own licenses. The original Simple Pyrate source and assets retain the BGGG MIT license. See licenses for included license text and these upstream projects for corresponding source, patches and build recipes:

- yt-dlp and its EJS scripts: https://github.com/yt-dlp/yt-dlp/tree/2026.10.26 and https://github.com/yt-dlp/ejs
- Deno: https://github.com/denoland/deno/tree/v2.9.8
- FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/release/8.1
- BtbN toolchain recipes, codec dependencies and configuration: https://github.com/FFmpeg-Builds/FFmpeg-Builds

Shipyard refreshes Windows system PATH copies without modifying the original bundled files.
