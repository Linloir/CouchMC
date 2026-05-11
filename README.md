# MC Controller

Turn your Android phone into a low-latency touchscreen controller for PC Java Edition Minecraft. Replicates the mobile MC control scheme (left joystick + right look pad + buttons) and injects keyboard/mouse events into the PC.

The clever bit is the **3-state mode system**: PC server detects whether MC has focus + cursor captured, and tells the phone to render different UIs (in-game controller / cursor-driving UI / lock screen) for each. That avoids having to mod Minecraft to mirror inventory/menus.

## Documentation

| Doc | Audience | What's in it |
|---|---|---|
| **[CLAUDE.md](CLAUDE.md)** | AI agents / new contributors | 5-minute orientation, key facts, file map |
| **[docs/architecture.md](docs/architecture.md)** | Anyone modifying code | Design rationale, module map, decision log, implementation status |
| **[docs/development.md](docs/development.md)** | Building / running / debugging | Toolchain, build commands, common pitfalls, test workflow |
| **[docs/protocol.md](docs/protocol.md)** | Anyone touching the wire | Byte-level wire format — single source of truth for PC + Android codecs |

## Status

Level 1 demo — under active development. Steps 0–10 and 14 done; Steps 11 (hotbar swipe-scroll), 12 (USB auto-config), 13 (latency polish) remain. See [docs/architecture.md § Implementation status](docs/architecture.md#8-implementation-status) for the full breakdown.

## Layout

```
mc_controller/
├── pc/         Windows server (.NET 8 WinForms, hosts tuning UI + TCP/UDP listeners)
├── android/    Android Kotlin app (touch input, network)
├── docs/       Protocol spec (single source of truth)
└── tools/      Helper scripts (adb reverse setup, etc.)
```

## Prerequisites

- Windows 10/11 with admin rights to install
- .NET 8 SDK (`winget install Microsoft.DotNet.SDK.8`)
- Android Studio Hedgehog (2023.1.1) or newer
- Android platform-tools (`adb`) on PATH
- Android device API 26+ (Android 8.0+) with USB debugging enabled
- Minecraft Java Edition (any recent version)
- For WiFi mode: PC and phone on the same LAN, ideally 5 GHz

## Quick start

```powershell
# 1. Start PC server (opens console + TuningForm)
cd E:\dev\personal\mc_controller\pc
dotnet run --project McController.Server

# 2. With phone on USB (debugging enabled):
adb reverse tcp:34555 tcp:34555
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.mccontroller/.ui.ConnectActivity

# 3. On the phone: tap "Connect (USB)". HUD should show "● USB · ... · Xms".
```

See [docs/development.md](docs/development.md) for WiFi mode, debugging, common errors, and the full iteration loop.

### Critical pre-game settings

Before testing camera control on a new machine:

1. Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options
2. **Uncheck "Enhance pointer precision"** — this disables OS-level mouse acceleration so the controller can drive a linear mapping
3. Inside Minecraft, set Mouse Sensitivity to **100%** as a baseline. Tune feel via the TuningForm's `Look (User) → Sensitivity` slider (default 1.5).

## License

Personal project. No license granted.
