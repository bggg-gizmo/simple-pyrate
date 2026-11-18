# Restore bundled files in a Git checkout

The Windows release ZIP includes its x64 and ARM64 tools. The Android source release ZIP includes the native payloads, bundled yt-dlp, and original icon art. Git tracks the app code, generated icon resources, artwork used at runtime, tests, notices, and dependency manifests. The large bundles are release assets.

For Windows, download `Simple-Pyrate-2.6.3-Windows.zip`. For Android, download `Simple-Pyrate-2.6.3-Android-Source.zip`. From the checkout root, pass the path to the archive you downloaded to the restore script.

```sh
python3 scripts/restore-release-runtime.py /path/to/Simple-Pyrate-2.6.3-Android-Source.zip
```

The same command works with the matching Windows release ZIP. The script only reads local files, validates the entire SHA-256 against `SHA256SUMS.txt`, and restores the pinned runtime files without replacing an existing file with different contents. It does not require Git LFS, administrator rights, or a network client. Windows users launching from the full Windows ZIP need not run it. Android users with the extracted full source ZIP can build directly.
