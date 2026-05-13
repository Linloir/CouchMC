# MC Controller — iOS Client

The iOS client of MC Controller. Mirrors the Android client's feature set
(joystick + lookpad + buttons + hotbar, three-mode controller, layout
profiles, LAN discovery) using a native Swift/SwiftUI + UIKit stack.

> **No code reuse with Android** — the wire protocol is the only contract.
> See [../docs/protocol.md](../docs/protocol.md) and
> [../docs/discovery.md](../docs/discovery.md).

## Requirements

- macOS with Xcode 16+ (for iOS 18 SDK; iOS 26 SDK enables full Liquid Glass)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An iPhone running iOS 18+. The app is portrait on the home/settings
  screens and locks to landscape only during gameplay. (iPad is **not** a
  supported destination — `TARGETED_DEVICE_FAMILY = 1`; iPad users can
  still install the iPhone build via "Designed for iPhone" compatibility
  mode, but no iPad-specific layout is shipped.)

## Project layout

```
ios/
├── project.yml                 XcodeGen spec — generates the .xcodeproj
├── scripts/
│   └── generate_app_icon.swift Reproducible app-icon renderer
└── McController/
    ├── App/                    @main, root navigation
    ├── Core/                   Session, layout, profiles, settings, mode
    ├── Net/                    Protocol, codec, channels, transport, discovery
    ├── Input/                  Look-delta accumulator, sprint hysteresis
    ├── UI/
    │   ├── Components/         Reusable Views (Theme, HostStatusDot)
    │   ├── Screens/            HomeView / SettingsView / ControllerScreen / Editor
    │   └── Touch/              UIKit touch surfaces (Joystick, LookPad, Button, Hotbar)
    └── Resources/              Info.plist, Assets.xcassets, Localizable.xcstrings
```

## Build

```bash
cd ios
xcodegen generate
open McController.xcodeproj
```

In Xcode, set the development team on the `McController` target, then
**Run** (⌘R) on a connected device. The Simulator works for UI but cannot
send real touch input to a PC.

### One-liner CLI build

```bash
cd ios
xcodegen generate
xcodebuild -project McController.xcodeproj \
           -scheme McController \
           -configuration Debug \
           -destination 'generic/platform=iOS' \
           CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
           build
```

(Add `-allowProvisioningUpdates` and your development team when actually
deploying.)

### Regenerating the app icon

```bash
cd ios/scripts
swift generate_app_icon.swift
```

Re-renders the 1024 × 1024 icon (PNG, white background, isometric grass
block at ~72 % of canvas) and the in-app About card icons. Re-run after
changing any color in the source palette.

## Architecture summary

- **Wire protocol** — `Net/Protocol.swift` mirrors the PC's `Protocol.cs`
  and the Android `Protocol.kt` byte-for-byte. All integers big-endian.
  Joystick fixed-point ×10000, camera deltas tenths-of-pixel (×10).
- **Transport** — `HybridTransport` actor owns one TCP control connection
  (`NWConnection` with `noDelay`) and one optional UDP camera connection
  (`NWConnection.udp`). Handshake (HELLO/HELLO_ACK) blocks until ack or
  timeout. UDP gracefully degrades to TCP-framed `LOOK_DELTA_TCP` if the
  server doesn't advertise a UDP port.
- **Discovery** — `DiscoveryClient` listens on UDP `34556` for
  `MCCT v1 ANNOUNCE` broadcasts (Channel A) **and** browses Bonjour
  `_mccontroller._tcp.` (Channel B). Results deduped by `(ip, port)`,
  evicted after 5 s of silence.
- **Mode FSM** — The server decides the mode (InGame / UiInteract /
  AntiMistouch). The client renders the corresponding widget set and
  resets every per-widget gesture FSM on transition, releasing any held
  buttons to prevent stuck-key state on the PC.
- **Touch perf** —
  - All gesture-sensitive widgets are UIKit `UIView`s (SwiftUI gestures
    are too coarse for split-touch FSM).
  - We call `event.coalescedTouches(for:)` to capture intermediate
    samples on 120 Hz ProMotion devices.
  - `LookAccumulator` accumulates raw deltas in an atomic counter and
    flushes every 8 ms (~125 Hz) on a dedicated user-interactive timer —
    the touch handler is non-blocking.
  - Sub-pixel residuals are carried across calls so very-slow swipes
    don't quantize away.
- **Memory hygiene** — All `NWConnection`s are explicitly `cancel()`d in
  `viewWillDisappear` (controller VC) and `stop()` (DiscoveryClient).
  Pending PING entries older than 10 s are GC'd. The look-accumulator
  has a single bounded `Int32` pair — no unbounded growth anywhere.

## Differences from Android

| Feature                         | Android                | iOS                                  |
|---------------------------------|------------------------|--------------------------------------|
| USB connection                  | `adb reverse` TCP loop | **Not supported** (Wi-Fi only)       |
| Layout editor pinch-resize      | full                   | drag-reposition only in v1           |
| Volume-key binding              | yes                    | not exposed                          |
| In-app theme toggle             | n/a                    | iOS 18 standard **vs** Liquid Glass  |
| Bonjour discovery               | NsdManager             | `NWBrowser`                          |
| UDP broadcast listener          | UdpSocket              | `NWListener` (`.udp`)                |

## Local Network permission

iOS 14+ requires explicit user consent for local-network access. On
first launch the system displays an alert sourced from
`NSLocalNetworkUsageDescription` (already set in `Info.plist`).
If the user denies it, both UDP broadcast discovery and Bonjour silently
return zero hosts, so the home screen will show only manually added IPs.

## Troubleshooting

- **"No hosts in the discovered list"** — the iPhone must be on the same
  Wi-Fi network as the PC. Check the Local Network permission in
  Settings → Privacy → Local Network → MC Controller.
- **Cursor in MC's UI feels laggy** — confirm Wi-Fi 5 GHz / no 2.4 GHz
  congestion. The app falls back to TCP for camera deltas if UDP can't
  be opened; that adds framing overhead.
- **"Server busy"** — only one client may connect at a time. Disconnect
  the Android client first.
- **App freezes on landscape rotation** — Portrait + Landscape are
  intentionally separate per-screen (`AppDelegate.allowedOrientations`),
  not a Plist matter. Don't edit `UISupportedInterfaceOrientations` to
  try to force one or the other globally.

## Roadmap

- USB-tethering via Personal Hotspot (zero app-side work, document in UI)
- Layout-editor pinch-to-resize (v2)
- Latency overlay (P50/P99 RTT, UDP loss rate)
