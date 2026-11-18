# Bundled Android components

Simple Pyrate invokes independent open-source executables. It does not include or link the Kotlin wrapper from youtubedl-android.

- yt-dlp 2026.10.26 for Python, with its packaged JavaScript solver. Source: https://github.com/yt-dlp/yt-dlp/tree/2026.10.26 and https://github.com/yt-dlp/ejs. Asset digest and URL: vendor/release-assets.json.
- Python, FFmpeg, FFprobe, and QuickJS native payloads are the arm64-v8a and x86_64 executables and library archives distributed in Maven Central youtubedl-android library and ffmpeg AARs at version 0.18.1. See vendor/native-sha256.txt and vendor/maven-archives.json for exact payload and container identity.
- Native packaging source and setup: https://github.com/JunkFood02/youtubedl-android/tree/0.18.1
- Termux-based native build recipes and versioned patches: https://github.com/termux/termux-packages and https://github.com/yausername/youtubedl-android-builds
- Upstream native source: https://github.com/python/cpython/tree/3.12, https://github.com/FFmpeg/FFmpeg/tree/release/7.1, and https://bellard.org/quickjs/

The runtime carries its own licenses. Relevant license texts ship in licenses, which is distinct from the MIT license for the Simple Pyrate program and BGGG assets. The original APK signing certificate is unrelated to the licenses of its included third-party components.

The five WebP libraries in each FFmpeg archive are replaced with the same-SONAME, 16 KiB-aligned libwebp 1.6.0 packages from the official Termux repository. The two package hashes and immutable asset names are in vendor/webp-packages.json. Upstream source and build recipe are at https://github.com/webmproject/libwebp/tree/v1.6.0 and https://github.com/termux/termux-packages/tree/master/packages/libwebp. The original Maven jar identity remains recorded separately. The hash manifest covers the final modified payloads.

The APK was inspected for both arm64-v8a and x86_64. All loadable ELF segments in the shipped payload are 16 KiB aligned. This static check does not substitute for using a device running in 16 KiB mode.
