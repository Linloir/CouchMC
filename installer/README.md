# MC Controller — Installer

The Windows installer for MC Controller is built with [Inno Setup](https://jrsoftware.org/isinfo.php) (free, open-source). It produces a single `.exe` that:

- Installs per-user under `%LOCALAPPDATA%\Programs\McController` (no admin prompt).
- Drops Start-Menu shortcuts + an optional Desktop shortcut + an optional "Run at sign-in" registry entry.
- Registers an Add/Remove Programs entry so the user can uninstall cleanly.
- On uninstall, removes the install dir and the local error log unconditionally, then asks whether to also delete the user's profiles/config in `%APPDATA%\McController`.

## One-time setup

Install Inno Setup (only the build machine needs it):

```powershell
winget install --id JRSoftware.InnoSetup
```

## Build the installer

```powershell
# 1) Publish the app in Release config.
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 -t:Rebuild

# 2) Compile the Inno Setup script.
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\McController.iss
```

Output lands in `installer\out\McController-Setup-<version>.exe` (~80–90 MB — the WindowsAppSDK runtime is bundled so end users don't need a separate install).

## What the installer touches

| Location | Purpose | Removed on uninstall? |
|---|---|---|
| `%LOCALAPPDATA%\Programs\McController\` | App binaries (self-contained, includes WindowsAppSDK runtime) | yes |
| `%APPDATA%\McController\config.json` | User profiles + tuning | only if the user opts in at uninstall time |
| `%LOCALAPPDATA%\McController\errors.log` | Crash/error trail | yes |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\McController` | "Run at sign-in" — only present if the user enabled it (in-app toggle or installer checkbox) | yes |
| Start Menu shortcut | Launcher | yes |
| Desktop shortcut | Optional launcher | yes |

The in-app **全局设置 → 开机时启动** toggle and the installer's **Run at sign-in** checkbox both edit the same `HKCU\…\Run` value, so they stay in sync.

## Distributing to end users

The output `McController-Setup-<version>.exe` is the only file you hand out. Users don't need to install .NET, the Windows App SDK runtime, or any redistributable — everything is in the bundle.

The first time a user runs the unsigned installer, SmartScreen may show "Windows protected your PC" — they click **More info → Run anyway**. Code-signing the installer (an Authenticode cert) removes this prompt; that's left as a future enhancement.

## Portable distribution (alternative)

If you'd rather skip an installer entirely, the Release publish output dir is fully self-contained — just zip `pc\McController.App\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\` and hand someone that. They run `McController.App.exe` directly. The app's first launch creates `%APPDATA%\McController\` on its own.
