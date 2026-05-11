# macOS server — architecture + operating notes

Status: **shipping** as of 2026-05. Native Swift / SwiftUI app under
`mac/`. Speaks the same wire protocol + LAN discovery spec as the
Windows server, so an Android (or future iOS) client targeting either
host is correct by construction.

For build instructions and project layout, see
[mac/README.md](../mac/README.md). This document covers the design
decisions and macOS-specific quirks that wouldn't be obvious from
reading the code.

## 1. Framework choice — native SwiftUI, not Avalonia

`docs/porting.md` originally recommended Avalonia for code reuse with
the WinUI 3 app. We ended up going with native Swift / SwiftUI on
purpose, because the user wanted:

- Latest official Apple paradigm (SwiftUI + `NavigationSplitView`,
  `MenuBarExtra`, `SMAppService`, etc.).
- First-class Liquid Glass support (`.glassEffect()` is SwiftUI-only).
- Zero non-Apple runtimes — Apple's notarization pipeline + a clean
  developer-ID-signed `.app` is the goal.

Trade-off accepted: zero source reuse from the C# Core. We re-implement
~1,200 lines of protocol + input + transport in Swift. The wire spec
keeps the two implementations honest (a phone connecting to either
server has to see the same byte sequence).

## 2. Module map

```
mac/McController/
├── McControllerApp.swift   @main — WindowGroup + MenuBarExtra
├── AppDelegate.swift       AppKit lifecycle bridge (hide-to-bar)
├── AppEnvironment.swift    Singleton holder for ServerHost / Appearance
├── ContentView.swift       NavigationSplitView root
│
├── Core/
│   ├── Net/                Protocol + Messages + PacketCodec + TCP/UDP/Discovery
│   ├── Input/              Joystick→WASD mapper, ButtonRouter, CameraCurve
│   ├── Config/             ServerConfig + ConfigStore (Application Support)
│   └── Diag/               ConnectionStats
│
├── Platform/                ← macOS-specific surface area
│   ├── CGEventInjector.swift           CGEventPost-based input
│   ├── MacWindowMonitor.swift          NSWorkspace + AX + CGCursorIsVisible
│   ├── MacCursorInjector.swift         CGWarpMouseCursorPosition (UI mode)
│   └── AccessibilityPermission.swift   AXIsProcessTrusted prompt
│
├── Services/
│   ├── ServerHost.swift               Orchestrator (mirror of ServerHost.cs)
│   ├── ProfileManager.swift           View-side wrapper around the profile list
│   ├── AdbDiscovery.swift             Bundled adb + auto `reverse`
│   ├── StartupRegistration.swift      SMAppService.mainApp toggle
│   └── AppearancePreferences.swift    Liquid Glass mode persistence
│
├── UI/                       SwiftUI pages — one per WinUI 3 page
└── Util/Localization.swift   Hand-rolled ZH-Hans + EN dictionary
```

The split mirrors the [Windows project's
McController.Core / McController.App boundary](../pc/McController.Core/),
just expressed in Swift conventions (no separate Xcode targets — one
app target, internal access control segregates the layers).

## 3. The 3-state mode system on macOS

Mode detection is structurally identical to Windows
(`Diag/WindowStateMonitor.cs`), with platform-specific primitives:

| Concern | Windows | macOS |
|---|---|---|
| Foreground window | `GetForegroundWindow()` + `GetWindowThreadProcessId` + `Process.GetProcessById().ProcessName` | `NSWorkspace.shared.frontmostApplication.bundleIdentifier` / `localizedName` / `executableURL` |
| Cursor visibility | `GetCursorInfo().flags == 0` | `CGCursorIsVisible()` — private CG function used by Steam / Unity / GLFW / SDL; stable since 10.4 |
| Active window rect | `GetClientRect` + `ClientToScreen` | `AXUIElementCopyAttributeValue(AXFocusedWindow, kAXPosition/kAXSize)` |
| Mouse delta injection | `SendInput(MOUSEEVENTF_MOVE)` relative | `CGEventCreate(kCGEventMouseMoved)` + `kCGMouseEventDeltaX/Y` |
| Mouse button | `SendInput(MOUSEEVENTF_*DOWN/UP)` | `CGEventCreate(left/right/otherMouseDown/Up)` |
| Cursor warp (UI mode) | `SetCursorPos` | `CGWarpMouseCursorPosition` + `CGAssociateMouseAndMouseCursorPosition(1)` to bypass the 250 ms arrival filter |
| Keyboard scancodes | Windows hardware scancodes | macOS `kVK_*` virtual key codes |

The scancode constants differ between Windows and macOS, but the
**ButtonId values on the wire are identical** — the platform layer
translates ButtonId → key code at the binding-resolution step
(`ButtonRouter.resolveBindings`).

## 4. Liquid Glass support

Three-way switch in **全局设置 → 外观**:

| Setting | macOS 26+ behavior | macOS 14/15 behavior |
|---|---|---|
| 跟随系统 | Glass surfaces | Standard `.regularMaterial` |
| 开启 | Glass surfaces | Standard `.regularMaterial` (no glass available) |
| 关闭 | Solid backgrounds | Solid backgrounds |

The glass code path is guarded by `#if compiler(>=6.2)` (Xcode 17+) AND
a runtime `if #available(macOS 26, *)` check. When building with Xcode
16 the glass branch is conditionally compiled out, so the binary still
runs on macOS 14+ without referencing symbols that don't exist in the
SDK we built against. When the project is opened in Xcode 17 the glass
branch activates automatically — no source changes required.

See `UI/LiquidGlass.swift` for the single point of customization.

## 5. Accessibility permission

`CGEventPost(.cghidEventTap, ...)` requires the process to be in
System Settings → Privacy & Security → Accessibility. Without it,
events are silently dropped — the user types but MC sees nothing.

`McControllerApp.body.task` calls
`AccessibilityPermission.ensurePromptIfNeeded()` once on launch, which
surfaces the system prompt the first time. The Discovery view shows a
prominent card with an "Open System Settings" button until the
permission is granted, polling `AXIsProcessTrusted()` every 2 s so the
state flips green within ~2 s of the user toggling the permission.

The app is **not sandboxed** (see `Resources/McController.entitlements`).
Accessibility + bundled adb subprocess + raw CG events all need
unsandboxed access. Distribution will be direct-download (Developer ID
+ notarization), not the Mac App Store.

## 6. ADB integration

Bundled at `McController.app/Contents/Resources/adb/adb`. Run
`mac/scripts/fetch-adb.sh` once to populate `mac/McController/Resources/adb/`
before building — the Xcode resources phase copies the directory into
the .app bundle.

`Services/AdbDiscovery.swift` polls `adb devices` every 3 s, caches
device model + "is the controller app installed", and auto-fires
`adb reverse tcp:<port> tcp:<port>` on every newly-ready USB device.
Logic 1:1 with `AdbDiscovery.cs`. If the bundled binary is missing,
falls back to `$PATH` so a dev-built app with no `fetch-adb.sh` run
still works on machines that have Android platform-tools installed
via Homebrew.

## 6.5 Menu bar status item — interaction with managers

The menu bar item is created via SwiftUI `MenuBarExtra("…", image:
"MenuBarIcon")` registered at scene-graph time. The asset's
`template-rendering-intent` is `template`, so the cube renders black
on light menu bars and white on dark ones automatically.

**Gotcha**: third-party menu-bar managers (Hidden Bar, Bartender,
iStat Menus, Vanilla) auto-hide newly-registered status items —
they're created but pushed off-screen at large negative X coordinates.
`mac/README.md` § "Menu bar item not visible?" has a one-liner to
verify the item exists, and the workflow for revealing / whitelisting
it. We deliberately *don't* try to fight the manager — that path
requires private API and would surprise users who installed the
manager specifically to declutter their bar.

## 7. Lifecycle — close button vs. quit

Mirroring the Windows tray hide-to-bar pattern:

- Closing the window does **not** quit the app. The server keeps
  running; the menu bar item is the visible signal.
  (`AppDelegate.applicationShouldTerminateAfterLastWindowClosed → false`.)
- The menu bar item has two entries: "Open Panel" (re-shows the
  window) and "Quit Service" (calls `NSApp.terminate(nil)`).
- `applicationWillTerminate` is the only path that calls
  `ServerHost.stop()`, which releases held keys, stops the listeners,
  and shuts down the discovery advertiser.

## 8. Configuration locations

Following Apple conventions:

| Path | Replaces (Windows) |
|---|---|
| `~/Library/Application Support/McController/config.json` | `%APPDATA%\McController\config.json` |
| `~/Library/Application Support/McController/appearance.json` | `%APPDATA%\McController\appearance.json` |
| `SMAppService.mainApp` state | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\McController` |
| `os_log` / Console.app | `%LOCALAPPDATA%\McController\errors.log` |

`ConfigStore.applicationSupportDirectory()` returns the same
`Application Support` URL the system would for any well-behaved app —
`FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, ...)`.
We don't write anywhere else, so uninstalling is just trashing the
.app bundle plus the Application Support directory.

## 9. Things that probably surprise a porter

- **`CGCursorIsVisible()` is private but stable**. Every Mac game
  runtime uses it. Apple has never broken it and a public replacement
  hasn't shipped — when one does, replace the `@_silgen_name` bridge
  in `MacWindowMonitor.swift` with the public call.
- **`CGWarpMouseCursorPosition` has a 250 ms input filter**.
  Subsequent `CGEventGetLocation` calls return the *pre-warp* location
  for ~250 ms unless you re-associate with
  `CGAssociateMouseAndMouseCursorPosition(1)`. We re-associate after
  every warp so cursor-mode tracking stays accurate.
- **`AXUIElementCopyAttributeValue` doesn't work on the Dock
  process**. The MC window's PID is what we care about and that's
  fine, but if you ever query `kAXMainWindowAttribute` on the Dock you'll
  get a generic error.
- **Bonjour publishes via `NWListener.service`**. We allocate a
  short-lived `NWListener` on an ephemeral port purely to register
  the service record; the actual TCP server is the long-lived
  `TcpServer` on `Config.port`. This is the canonical pattern from
  Apple's Bonjour migration guide.
- **`Process.run()` adb output**. macOS doesn't have a
  "no shell expansion" problem like Windows, but `adb` writes
  warnings to stderr that we currently discard. If a probe failure
  is mysterious, redirect stderr to a temp file and inspect.
- **SMAppService requires the app to be in `/Applications`** for the
  login-item registration to succeed in some macOS versions. Running
  from `~/Library/Developer/Xcode/DerivedData/.../McController.app`
  registers but doesn't auto-launch — move the bundle into `/Applications`
  for that path to work end-to-end.
