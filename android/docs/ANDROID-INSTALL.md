# Install Simple Pyrate on Android

Download and tap `Simple-Pyrate-2.6.3-Android.apk`. The source ZIP is for rebuilding and is not an installer. Android 10 or newer and a 64-bit ARM or x86-64 device are required. If Android asks for permission to install from the app that opened the APK, grant it for the installation. No Gradle, SDK, ADB, Termux, or separately installed media tools are needed to run the APK.

The launcher uses the supplied gold ship artwork against a dark background. Android can mask the icon to the system's chosen launcher shape.

To verify a download, compare its SHA-256 against the corresponding checksum file. The APK and source ZIP have different SHA-256 values.

Android requires matching package names and signing certificates to update an installed app in place. If an earlier build was signed with a different key, use an APK rebuilt with that key for an in-place update. Back up any data you need before replacing an incompatible installation. The supplied APK was signed with a different certificate from 2.6.2. The archive does not include any signing key. Use your own retained key for a public release and subsequent updates.
