# MC Controller

Turn your Android phone into a low-latency touchscreen controller for PC Java Edition Minecraft. Replicates the mobile MC control scheme (left joystick + right look pad + buttons) and injects keyboard/mouse events into the PC.

## Status

Level 1 demo — under active development. See `app-mc-zesty-starlight.md` plan file for the implementation roadmap.

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

TBD — instructions added as implementation progresses.

### Critical pre-game settings

Before testing the camera control:

1. Open Windows Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options
2. **Uncheck "Enhance pointer precision"** — this disables OS-level mouse acceleration, giving the controller a linear mapping
3. Inside Minecraft, set Mouse Sensitivity to 100% as a baseline; tune the controller's `userSensitivity` in the PC tuning UI instead

## Protocol

See [docs/protocol.md](docs/protocol.md) for the wire format.

## License

Personal project. No license granted.
