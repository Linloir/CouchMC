# MC Controller

Turn your phone into a low-latency touchscreen controller for PC Java Edition Minecraft. Replicates the mobile MC control scheme (left joystick + right look pad + buttons) and injects keyboard/mouse events into the PC.

The clever bit is the **3-state mode system**: the PC server detects whether MC has focus + cursor captured, and tells the phone to render different UIs (in-game controller / cursor-driving UI / lock screen) for each. That avoids having to mod Minecraft to mirror inventory/menus.

## Documentation

| Doc | Audience | What's in it |
|---|---|---|
| **[CLAUDE.md](CLAUDE.md)** | AI agents / new contributors | 5-minute orientation, key facts, file map |
| **[docs/architecture.md](docs/architecture.md)** | Anyone modifying code | Design rationale, module map, decision log, implementation status |
| **[docs/development.md](docs/development.md)** | Building / running / debugging | Toolchain, build commands, common pitfalls, test workflow |
| **[docs/protocol.md](docs/protocol.md)** | Anyone touching the wire | Byte-level wire format — single source of truth for PC + Android codecs |
| **[docs/discovery.md](docs/discovery.md)** | LAN-discovery integration | UDP-broadcast / mDNS announce format + the PROBE reachability check |
| **[docs/porting.md](docs/porting.md)** | Planning the iOS / macOS ports | Platform boundaries, recommended project split, framework choices |
| **[installer/README.md](installer/README.md)** | Cutting a Windows release | Inno Setup build steps, what the installer touches, uninstall behavior |

## Platform support

| Target | Status |
|---|---|
| **Windows 10/11** (server) | ✅ Shipping — WinUI 3 app with installer |
| **Android 8.0+** (client) | ✅ Shipping — Kotlin app |
| **macOS** (server) | Planned — see [docs/porting.md](docs/porting.md) |
| **iOS** (client) | Planned — see [docs/porting.md](docs/porting.md) |

The wire protocol (`docs/protocol.md`) and the LAN discovery spec (`docs/discovery.md`) are deliberately platform-agnostic: an iOS client talking to a macOS server, or any cross-pair, is correct by construction once both implementations exist. The bulk of `McController.Core` is portable .NET; the Windows-specific layer is small enough to swap out cleanly. See `docs/porting.md` for the playbook.

## Status

Distribution-ready demo. The PC server has an Inno Setup installer that hands users a single `.exe`, registers an Add/Remove Programs entry, supports per-user "run at sign-in", and stores config under `%APPDATA%\McController\` so uninstall cleans up properly.

Recent work:
- 全局设置 / 关于 footer pages with i18n (ZH-Hans / EN)
- Tray icon + hide-to-tray (close button doesn't kill the service)
- Window transparency prefs (Acrylic on/off + per-region opacity sliders)
- LAN discovery — phone connect screen auto-lists running servers
- USB mode auto-`adb reverse` on device detection

See [docs/architecture.md § Implementation status](docs/architecture.md#8-implementation-status) for the full breakdown.

## Layout

```
mc_controller/
├── pc/          .NET 8 solution: Core library + WinUI 3 shell + xUnit tests
├── android/     Android Kotlin client
├── installer/   Inno Setup script for the Windows installer
├── docs/        Wire spec, design rationale, porting plan
└── tools/       Helper scripts
```

## Prerequisites

- Windows 10/11
- .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`)
- Visual Studio 2022 Build Tools — the **"Windows App SDK C# Templates"** workload is required for the WinUI 3 build pipeline (`Pri.Tasks.dll`). Plain `dotnet build` is enough for `McController.Core` but the App project needs the VS BuildTools MSBuild
- Android Studio Hedgehog (2023.1.1) or newer (for the phone app)
- Android platform-tools (`adb`) on PATH
- Android device API 26+ (Android 8.0+) with USB debugging enabled
- Minecraft Java Edition (any recent version)
- For WiFi mode: PC and phone on the same LAN, ideally 5 GHz

## Quick start

```powershell
# 1. Build + run PC server
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    E:\dev\personal\mc_controller\pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64
Start-Process E:\dev\personal\mc_controller\pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe

# 2. With phone on USB (debugging enabled), the PC auto-fires adb reverse.
#    No manual step needed — but if you want to verify:
adb reverse --list                  # expect "tcp:34555 tcp:34555" per device

# 3. Build + install + launch the Android app
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.mccontroller/.ui.ConnectActivity

# 4. On the phone: pick a discovered server (LAN) or tap "Connect (USB)".
#    HUD shows "● USB · ... · Xms" once connected.
```

For end-user distribution, build the Inno Setup installer instead — see [installer/README.md](installer/README.md). The resulting `McController-Setup-<version>.exe` is the only file you hand out (~80–90 MB, fully self-contained).

See [docs/development.md](docs/development.md) for WiFi mode, debugging, common errors, and the full iteration loop.

### Critical pre-game settings

Before testing camera control on a new machine:

1. Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options
2. **Uncheck "Enhance pointer precision"** — disables OS-level mouse acceleration so the controller can drive a linear mapping
3. Inside Minecraft, set Mouse Sensitivity to **100%** as a baseline. Tune feel via the in-app Settings → 视角 → Sensitivity slider (default 1.5).

## License

Personal project. No license granted.
