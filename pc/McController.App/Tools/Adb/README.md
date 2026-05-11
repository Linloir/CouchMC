# Bundled Android Debug Bridge (adb)

These files are the Windows binaries from **Android SDK Platform-Tools**, bundled with MC Controller so end users don't need to install the Android SDK separately to enable USB-mode device discovery and port forwarding.

## What's here

| File | Purpose |
|---|---|
| `adb.exe` | The Android Debug Bridge client + daemon |
| `AdbWinApi.dll` | Windows USB API wrapper (required by `adb.exe`) |
| `AdbWinUsbApi.dll` | WinUSB API wrapper (required by `adb.exe`) |
| `NOTICE.txt` | Upstream attribution notice for the Android SDK Platform-Tools distribution |

## Version

Android Debug Bridge **1.0.41** (Platform-Tools **37.0.0-14910828**), pulled from `https://dl.google.com/android/repository/platform-tools-latest-windows.zip`.

## License

Licensed under the **Apache License, Version 2.0** — see <https://www.apache.org/licenses/LICENSE-2.0> for the full text. The upstream `NOTICE.txt` is preserved alongside the binaries.

## Refreshing

To pull a newer release, replace the three binaries (and `NOTICE.txt`) with the contents of the latest `platform-tools-latest-windows.zip` — that's all that's needed. No code in the project hard-codes the version.

## Why bundle instead of `winget install`?

End users get one self-contained installer. `AdbDiscovery` shells out to this bundled `adb.exe` first; if it's missing for any reason, it falls back to `adb` on `PATH` so dev environments that already have it set up keep working.
