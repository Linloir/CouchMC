# Porting plan — macOS server + iOS client

> **macOS server: shipping** as of 2026-05 — native Swift / SwiftUI app under `mac/`. See [docs/macos.md](macos.md) for the actual architecture + operating notes. The discussion below is preserved for two reasons: (1) it documents the design alternatives we considered before settling on native Swift, and (2) the iOS-client section is still the active plan. The "Suggested migration order" section is now historical — the actual order taken is reflected in git history.

The fundamental observation is that **the wire format and the LAN-discovery spec are platform-neutral** (see [protocol.md](protocol.md) and [discovery.md](discovery.md)), and **the bulk of `McController.Core` is also platform-neutral C# code**. The Windows-specific surface area is small and well-isolated. This means a cross-platform port doesn't need a rewrite — it needs a refactor of one project plus two new platform-specific projects.

---

## 1. What stays, what moves

### Already platform-neutral (no changes required)

- **The wire protocol** — `Net/Protocol.cs`, `Net/Messages.cs`, `Net/PacketCodec.cs`. All use `BinaryPrimitives` + plain integers. Already cross-platform C#.
- **TCP / UDP transport** — `Net/TcpServer.cs`, `Net/UdpServer.cs`. Use plain `Socket` / `UdpClient`. Cross-platform.
- **LAN discovery** — `Net/LanDiscoveryAdvertiser.cs`. Uses plain `UdpClient` with broadcast. Cross-platform.
- **Input *mapping*** — `Input/JoystickToWasdMapper.cs`, `Input/ButtonRouter.cs`, `Input/CameraCurve.cs`, `Input/IInputInjector.cs`, `Input/Scancodes.cs` (the constants are Windows scancodes, but they're constants — see § 5 for the remap split). Pure logic; takes `IInputInjector` as a dependency.
- **Config** — `Config/ServerConfig.cs`, `Config/ConfigStore.cs`. `System.Text.Json`. Cross-platform.
- **Diagnostics** — `Diag/ConnectionStats.cs`. Atomic counters. Cross-platform.
- **Tests** — `McController.Core.Tests` runs unchanged once Core is `net8.0` instead of `net8.0-windows`.

### Windows-specific (needs a macOS equivalent)

In `McController.Core` today (will move out in the refactor):

| File | Win32 API used | macOS equivalent |
|---|---|---|
| `Input/Win32InputInjector.cs` | `SendInput` (mouse + keyboard) | `CGEventCreateMouseEvent` / `CGEventCreateKeyboardEvent` + `CGEventPost(kCGHIDEventTap, …)` |
| `Input/CursorInjector.cs` | `SetCursorPos`, `GetClientRect`, `ClientToScreen` | `CGWarpMouseCursorPosition`; rect lookup via `CGWindowListCopyWindowInfo` filtering by owner-PID |
| `Diag/WindowStateMonitor.cs` | `GetForegroundWindow`, `GetWindowThreadProcessId`, `GetCursorInfo` | `NSWorkspace.shared.frontmostApplication` for foreground; cursor visibility via polling `CGCursorIsVisible()` (private) or installing a `CGEventTap` |
| `Input/InputLanguageManager.cs` | `LoadKeyboardLayout`, `PostMessage(WM_INPUTLANGCHANGEREQUEST)` | `TISCopyCurrentKeyboardInputSource` + `TISSelectInputSource`. (Not wired even on Windows; defer for the port too.) |
| `Diag/PrecisionTimer.cs` | `timeBeginPeriod` | macOS already gives 1 ms sleep granularity; this file becomes a no-op on Mac (or just `Thread.Sleep`). |

In `McController.App` (the entire project is WinUI 3 — the macOS shell is a separate, parallel project):

| Concern | Windows file | macOS approach |
|---|---|---|
| App shell | `App.xaml.cs`, `MainWindow.xaml(.cs)`, `Views/*` | See § 3 below — Avalonia is the recommended path. |
| Tray icon | `Services/TrayService.cs` (H.NotifyIcon) | `NSStatusItem` via Avalonia's `TrayIcon` API, or a small Cocoa P/Invoke if the cross-platform abstraction is too thin. |
| Start at login | `Services/StartupRegistration.cs` (HKCU\…\Run) | Write a `LaunchAgent` plist at `~/Library/LaunchAgents/com.linloir.mccontroller.plist` and `launchctl load` it. |
| Window backdrop | `MainWindow.xaml.cs` (`DesktopAcrylicBackdrop`) | macOS has native visual-effect views (`NSVisualEffectView`); Avalonia exposes this on macOS as `TransparencyLevelHint.AcrylicBlur` / `Mica`. |
| ADB integration | `Services/AdbDiscovery.cs` | Drop entirely — iOS has no `adb`. (See § 4.) |
| Installer | `installer/McController.iss` | `.app` bundle + DMG, optionally signed/notarized. |
| Config locations | `%APPDATA%\McController\` + `%LOCALAPPDATA%\McController\` | `~/Library/Application Support/McController/` + `~/Library/Logs/McController/`. The existing `ResolveDefaultConfigPath` already uses `Environment.SpecialFolder.ApplicationData`, which on macOS maps to the right place automatically. The `%LOCALAPPDATA%` path in `App.xaml.cs` needs explicit fan-out per OS. |

---

## 2. Recommended project layout after the refactor

```
mc_controller/
├── pc/
│   ├── McController.sln
│   ├── McController.Core/                  TFM: net8.0       (pure, no P/Invoke)
│   ├── McController.Core.Tests/             TFM: net8.0
│   ├── McController.Platform.Windows/      TFM: net8.0-windows  (Win32 P/Invoke)
│   │   ├── Win32InputInjector.cs
│   │   ├── Win32CursorInjector.cs
│   │   ├── Win32WindowStateMonitor.cs
│   │   ├── Win32StartupRegistration.cs    (HKCU Run key)
│   │   └── …
│   ├── McController.Platform.Mac/           TFM: net8.0        (Cocoa P/Invoke)
│   │   ├── MacInputInjector.cs            (CGEventPost)
│   │   ├── MacCursorInjector.cs           (CGWarpMouseCursorPosition)
│   │   ├── MacWindowStateMonitor.cs       (NSWorkspace + CGCursorIsVisible)
│   │   ├── MacStartupRegistration.cs      (LaunchAgent plist)
│   │   └── Cocoa/                          P/Invoke declarations for AppKit / CoreGraphics
│   ├── McController.App.Windows/           was McController.App (WinUI 3)
│   └── McController.App.Mac/                new — Avalonia (or native Swift, see § 3)
└── android/  ios/  …
```

The key interfaces that the platform projects implement (already in `Core`):

```csharp
public interface IInputInjector { … }                // already exists
public interface IWindowStateMonitor { … }           // promote from Win32WindowStateMonitor's public surface
public interface ICursorInjector { … }               // promote from CursorInjector
public interface IStartupRegistration { … }          // new
```

`McController.Core` defines the interfaces and the orchestration (`ServerHost`-style class). Each platform project provides the implementations and is referenced by the matching App.

---

## 3. Mac app shell — the framework choice

Three viable options, in descending order of code reuse:

### What we actually picked (post-decision)

**Native Swift / SwiftUI.** Zero source reuse from `McController.Core`,
but the user wanted Apple's official paradigm (SwiftUI, `MenuBarExtra`,
`SMAppService`, Liquid Glass) and that ruled the Avalonia + .NET MAUI
options out. The wire protocol does the same job as a shared library
would: keep the two implementations honest. See [docs/macos.md](macos.md)
for the resulting architecture.

The Avalonia / MAUI / "Swift driving headless .NET" trade-off summary
below remains useful as reference for anyone re-evaluating later.

### Option A: Avalonia (originally recommended)

**Pros**:
- XAML-based, similar enough to WinUI 3 that the `Views/*.xaml` files port with mechanical search/replace (different namespace URIs, slightly different control names, `tk:SettingsCard` → custom or `Card` etc.).
- The Settings / About / Discovery / GlobalSettings pages have no Windows-specific bindings; they all consume `McController.Core` objects.
- Native AppKit rendering on macOS via Avalonia 11's `MacOSPlatformOptions`. Tray icon, transparency (`AcrylicBlur`), and styled title bar are first-class.
- One codebase that also runs on Linux later, if it ever matters.

**Cons**:
- Avalonia is not WinUI 3 — there will be a couple of weeks of paper-cuts (different theming system, no `CommunityToolkit.WinUI.Controls.SettingsControls` equivalent so you'll rebuild `SettingsCard` as a styled `UserControl`).
- Less native polish than Apple's own frameworks; not a deal-breaker for a personal tool.

**Effort estimate**: 1–2 weeks for a working Mac port if the Core refactor is already done.

### Option B: .NET MAUI

**Pros**: Microsoft-blessed cross-platform; nominal code reuse from WinUI 3.

**Cons**: MAUI's macOS support (via Mac Catalyst) is the weakest of its three desktop targets; Catalyst itself is an UIKit-on-Mac shim, so the result looks "iPad-ish" rather than native. Not recommended for a daily-driver desktop app.

### Option C: Native Swift / SwiftUI app driving a headless .NET Core

**Pros**: Native Mac look-and-feel; best integration with macOS conventions (Sparkle for updates, sandboxing, notarization, etc.).

**Cons**: Need an IPC layer between the Swift UI and the .NET server process (XPC, local TCP, or named pipes). Doubles the maintenance burden — bugs split across two ecosystems. Only worth it if the polish target is high.

**Recommendation**: **Option A (Avalonia)**. Move to Option C only if Avalonia falls short of the polish bar.

---

## 4. iOS client

The iOS app is **a from-scratch Swift port** of the Android codebase. There's no useful code reuse between Kotlin and Swift, but there's plenty of design reuse — every architectural decision (layout system, gesture FSM, transport split, mode handling) carries over verbatim.

### Recommended structure

```
ios/
├── McController.xcodeproj
└── McController/
    ├── App/
    │   ├── McControllerApp.swift           SwiftUI @main; owns the ControllerSession
    │   └── ContentView.swift                Top-level routing (Connect ↔ Controller ↔ Editor)
    ├── Core/
    │   ├── ControllerSession.swift          Lifecycle (mirror of Kotlin's)
    │   ├── ControllerMode.swift             enum InGame / UIInteract / AntiMistouch
    │   ├── LayoutSpec.swift                 WidgetSpec / ModeLayout / LayoutProfile
    │   ├── ProfileStore.swift               JSON in UserDefaults (or in Documents)
    │   └── LayoutApplier.swift              Translates anchor → UIView frame
    ├── Net/
    │   ├── Protocol.swift                   Constants — MIRROR of PC's and Android's
    │   ├── PacketCodec.swift                encode / decode using Data + UnsafeBytes
    │   ├── TCPChannel.swift                 NWConnection (Network framework)
    │   ├── UDPChannel.swift                 NWConnection .udp
    │   ├── HybridTransport.swift            TCP + optional UDP, handshake
    │   └── LanDiscoveryListener.swift       NetServiceBrowser (Bonjour) — Channel B
    ├── Input/
    │   └── LookAccumulator.swift            8 ms flush coroutine; uses DispatchSourceTimer
    ├── UI/
    │   ├── ConnectView.swift                SwiftUI — server picker, profile picker
    │   ├── ControllerView.swift             SwiftUI hosting a custom UIView for gestures
    │   ├── JoystickView.swift               UIView subclass (touchesBegan/Moved/Ended)
    │   ├── LookPadView.swift                Custom UIView + the 10-state gesture FSM
    │   ├── ActionButtonView.swift            HOLD / TOGGLE / TAP modes
    │   ├── HotbarView.swift                 9 slots, swipe + long-press semantics
    │   └── LayoutEditorView.swift           Edit mode (selection-based)
    └── Resources/
        ├── Assets.xcassets
        └── Localizable.strings              ZH-Hans + EN (mirror of Util/L.cs)
```

### Apple-specific design notes

- **Multi-touch + low-latency input**: SwiftUI's `DragGesture` is too high-level (insufficient pointer-id control). Use a custom `UIView` subclass with the four `touchesBegan/Moved/Ended/Cancelled` callbacks, just like the Kotlin app uses `View.onTouchEvent`. Wrap the `UIView` in a `UIViewRepresentable` and embed in SwiftUI.
- **Network framework over BSD sockets**: `NWConnection` is the modern, recommended way. `Network` is also where TCP_NODELAY-equivalent options live (`NWParameters.tcp.noDelay = true`).
- **Discovery via Bonjour (Channel B)** is more pleasant on iOS than UDP broadcast (Channel A). `NetServiceBrowser.searchForServices(ofType: "_mccontroller._tcp.", inDomain: "local.")` is one line. Still implement Channel A as a fallback (some routers drop mDNS).
- **Keep-screen-on**: `UIApplication.shared.isIdleTimerDisabled = true` while the controller is connected.
- **Landscape lock**: set `UIInterfaceOrientationMaskLandscape` in Info.plist + `supportedInterfaceOrientations` override.
- **Immersive UI**: hide status bar with `preferredStatusBarStyle` + `prefersStatusBarHidden` on the controller view's view controller, and home-indicator-auto-hidden via `prefersHomeIndicatorAutoHidden`.
- **Haptics**: free upgrade. `UIImpactFeedbackGenerator(.rigid).impactOccurred()` on button taps. The Android side doesn't have this yet; could come back to retrofit symmetrically.

### USB connectivity — the hard part

iOS has no equivalent to `adb reverse`. Options ranked by practicality:

1. **WiFi-only** *(strongly recommended for v1)*. Same-network connection covers 95 % of the use case. The 5 GHz home LAN latency budget is fine. Discovery via Bonjour makes setup trivial.
2. **USB tethering** ("Personal Hotspot → Allow others to join → connect Mac via USB"). The iPhone shows up as `iPhone USB` network interface on the Mac with a real `192.168.x.x` address; the Mac talks to the phone as a normal LAN peer. No app-side work needed. Caveat: the user has to toggle Hotspot every session.
3. **MFi External Accessory**. Apple's `ExternalAccessory` framework can carry arbitrary data over Lightning / USB-C. **Requires Apple's MFi accessory certification** (limited to vendors), which is a non-starter for personal tooling.
4. **Local network over IP-over-USB (libimobiledevice / `usbmuxd`)**. Possible from the Mac side using `usbmux` socket tunneling; iOS side just sees a regular `localhost` TCP. Works but requires `usbmuxd` running on the host and a fixed port mapping — complex to set up for end users.

**Recommendation**: ship WiFi-only first. Add USB tethering as a documented workflow (no code changes needed — just point the user at the Personal Hotspot toggle). Revisit option 4 if there's demand.

---

## 5. Suggested migration order

If/when the port begins, this is the sequence that keeps the existing Windows build healthy the whole time:

1. **Refactor `McController.Core` to TFM `net8.0`**.
   - Extract `Win32InputInjector`, `CursorInjector`, `WindowStateMonitor`, `PrecisionTimer`, `InputLanguageManager`, `SelfTest` into a new `McController.Platform.Windows` project.
   - Promote `WindowStateMonitor`'s public surface into `IWindowStateMonitor` in Core.
   - Promote `CursorInjector` similarly to `ICursorInjector`.
   - Move `Services/StartupRegistration.cs` from `McController.App` into `McController.Platform.Windows` as `Win32StartupRegistration : IStartupRegistration`.
   - Add a thin "compose root" in Core that takes the interface set as inputs.
   - **Verify**: existing `McController.App` builds and runs; tests pass.
2. **Add `McController.Platform.Mac` skeleton** — empty stubs for each interface, returning sensible no-ops or throwing `NotImplementedException`. Builds on Windows under `dotnet build`. Confirms the multi-target plumbing works.
3. **Get the Mac platform shim running on a Mac**. On a Mac with the .NET 8 SDK installed (`brew install --cask dotnet-sdk`), implement each Platform.Mac class one at a time, smoke-tested with a console harness in `McController.Core` that runs the existing `SelfTest`-style routines against the Mac injector.
4. **Stand up `McController.App.Mac`** in Avalonia. Re-host the existing pages one at a time: Discovery → Settings → GlobalSettings → About. Reuse the page-side code that talks only to `Core` types.
5. **Build the iOS app from scratch** mirroring the Android architecture. The PC server is unchanged for this step (it doesn't care whether the client is Android or iOS — the wire is identical).
6. **iOS LAN discovery**: ship with Bonjour (Channel B) first; Channel A (UDP broadcast listener) is a nice-to-have.

Each step's "Done" criterion is **a working end-to-end demo on the new platform** — not "the code compiles." Don't merge a step until the demo is reproducible.

---

## 6. Things that will probably surprise the porter

- **Cursor capture on macOS** is GLFW's job inside Minecraft, the same as on Windows — but checking *whether* MC has the cursor captured is much harder. `CGCursorIsVisible()` (private API; works but unsupported) or an event-tap approach is the path. MC's behavior is identical across OSes once cursor capture works, so the mode detection logic itself is unchanged.
- **macOS Accessibility permission**: posting `CGEvent`s requires the user to grant Accessibility permission to the app (System Settings → Privacy & Security → Accessibility). The app needs to detect this and prompt the user the first time. Use `AXIsProcessTrusted()` to check.
- **Sandboxing**: do NOT sandbox the macOS app. CGEventPost and Accessibility don't play with sandbox limits. Distribute via direct download + Developer ID signing + notarization, not via the App Store.
- **iOS `Network` framework default queues are the main queue** — set `connection.start(queue: .global(qos: .userInteractive))` or input will stall behind UI updates.
- **iOS multi-touch on UIView**: pointer ID tracking works the same as Android, but `UITouch` objects are persisted across events — diff by reference (`===`), not by an explicit ID field.
- **Apple's mDNS implementation deduplicates Bonjour broadcasts very aggressively**. If you have both Channel A (UDP broadcast) and Channel B (Bonjour) sending from the same Mac, the same host appears twice on the iOS client — dedup keyed by `(ip, tcpPort)` (as the spec already says).

---

## 7. Out of scope

- **Linux server**. The wire spec is portable, but the input-injection layer would need `uinput` plumbing and X11 vs. Wayland branching. Not planned.
- **Windows Phone / older Android (< 8.0)**. Min SDK is API 26 and that's not budging.
- **Cross-Apple-ecosystem on the *PC side***. Sharing UI code between the Mac app and an iPad-as-PC-host setup is theoretically possible (Mac Catalyst) but ill-advised given the gesture differences between the two roles.
