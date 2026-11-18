# Restore bundled files in a Git checkout

The full Windows package includes its x64 and ARM64 tools. The full Android source archive includes the native payloads, bundled yt-dlp, and original icon art. The `main` branch tracks app code, generated icon resources, artwork used at runtime, tests, notices, and dependency manifests. The full packages are not hosted on GitHub.

If you have a matching archive from the maintainer, place it in the checkout root or pass its actual local path. Windows requires `Simple-Pyrate-2.6.3-Windows.zip` to restore the bundled files. Android requires `Simple-Pyrate-2.6.3-Android-Source.zip` for the packaged runtime. Windows can also install dependencies through Shipyard without the archive.

```sh
python3 scripts/restore-release-runtime.py Simple-Pyrate-2.6.3-Android-Source.zip
```

The same command works with the matching full Windows ZIP. The script only reads local files, validates the entire SHA-256 against `SHA256SUMS.txt`, and restores the pinned runtime files without replacing an existing file with different contents. It does not require Git LFS, administrator rights, or a network client. Windows users launching from the full Windows ZIP need not run it. Android users with the extracted full source ZIP can build directly.
