# CLAUDE.md — AI Agent Orientation

This file is the first thing an AI coding agent should read when picking up work on this project. It points to the canonical docs and summarizes context that's stable across sessions.

## The 10-second pitch

Turn an Android phone into a touchscreen controller for PC Java Edition Minecraft. Phone runs a Kotlin app that captures touch (joystick + look pad + buttons) and streams input events to a Windows `.NET 8 + WinUI 3` server that injects keyboard/mouse via `SendInput`.

The **key architectural insight** is the 3-state mode system: instead of mirroring MC's inventory/menu UIs over the wire, the PC detects MC's window+cursor state (`WindowStateMonitor`) and tells the phone which mode to render — in-game (full controller), UI-interact (lookpad drives cursor + small button set), or anti-mistouch (lock screen).

## Canonical docs (in order)

1. **[docs/architecture.md](docs/architecture.md)** — design rationale, module map, decision log
2. **[docs/development.md](docs/development.md)** — build / install / debug workflow, common pitfalls
3. **[docs/protocol.md](docs/protocol.md)** — wire protocol (single source of truth for PC/Android codecs)
4. **[docs/discovery.md](docs/discovery.md)** — LAN announce / probe wire formats
5. **[docs/porting.md](docs/porting.md)** — cross-platform plan (macOS server + iOS client)
6. **[README.md](README.md)** — user-facing prerequisites + quick start
7. **[installer/README.md](installer/README.md)** — Inno Setup build instructions

The plan file at `~/.claude/plans/app-mc-zesty-starlight.md` is **not portable across machines** — treat docs/architecture.md as authoritative.

## Layout

```
mc_controller/
├── pc/                              .NET 8 solution
│   ├── McController.sln
│   ├── McController.Core/           protocol + input + diag + config
│   ├── McController.Core.Tests/     xUnit, 53 tests
│   └── McController.App/            WinUI 3 desktop shell (Windows-only)
├── android/                         Gradle / Kotlin Android app
│   ├── settings.gradle.kts
│   └── app/src/main/...
├── installer/                       Inno Setup script for Windows distribution
├── docs/                            spec + design + workflow
└── tools/                           helper scripts
```

## Key technical facts

- **PC core**: C# / .NET 8 (`McController.Core`, currently TFM `net8.0-windows` because some files use Win32 P/Invoke — see [docs/porting.md](docs/porting.md) for the split planned for the Mac port).
- **PC shell**: WinUI 3 (`McController.App`, `WindowsAppSDK 1.7`, self-contained publish via `WindowsAppSDKSelfContained=true`). NavigationView sidebar + footer items (全局设置, 关于), tray icon via `H.NotifyIcon.WinUI`, `DesktopAcrylicBackdrop` for the window background.
- **Android language**: Kotlin 1.9.22, AGP 8.2.2, min SDK 26, target 34, view binding.
- **Transport**: TCP for control + UDP for camera deltas (WiFi only — USB mode via `adb reverse` is TCP-only, with `LOOK_DELTA_TCP` fallback).
- **Wire frame**: length-prefixed binary, big-endian. Camera deltas are in tenths-of-pixel (`SUBPIXEL_SCALE = 10` on both ends).
- **Default port**: 34555 (control), 34556 (LAN discovery broadcast).
- **Mode detection**: `WindowStateMonitor` polls `GetForegroundWindow()` + `GetCursorInfo()` every 100 ms with 1-tick debounce.
- **Cursor driving in UI mode**: `SetCursorPos` clamped to MC client rect (no global `ClipCursor`).
- **WASD mapping**: `JoystickToWasdMapper` with dead-zone, enter/exit hysteresis, and `<=` comparison for release (so `0` everywhere still releases — regression-tested).
- **Sub-pixel residuals**: `LookPadView`, `ActionButtonView` (HOLD-mode drag), `CameraCurve` all carry fractional remainders across calls.
- **Gesture FSM** for `LookPadView`: hand-rolled (not `GestureDetector`), ~10 states. In-game: zero-latency tap + chained LMB-held via double-press. UI mode: 200 ms wait for single-tap; double-tap → RMB; "tap + re-press + slide" → LMB hold; "double-tap + re-press + slide" → RMB hold. State resets on mode change (releases any held button).
- **Layout system**: every editable widget is described by a `WidgetSpec(anchor, edge, vert, w, h)`; `LayoutApplier` writes margins/gravity onto `FrameLayout.LayoutParams`. Profiles persisted in SharedPreferences as JSON.
- **User config locations** (Windows):
  - `%APPDATA%\McController\config.json` — controller / profile tuning (`ServerHost.ResolveDefaultConfigPath`)
  - `%APPDATA%\McController\appearance.json` — window transparency prefs (`AppearancePreferences`)
  - `%LOCALAPPDATA%\McController\errors.log` — unhandled exception trail
  - `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\McController` — "start at sign-in" flag (`StartupRegistration`)

## Conventions

- **Wire deltas are tenths-of-pixel** (×10 from finger px). Android scales up, PC scales down.
- **Joystick output** is fixed-point i16 with scale 10000 (so `0.5f` → `5000`).
- **`Anchor.BottomCenter` / `TopCenter`** ignore `edgeMarginDp` (horizontal always centered) and global L/R offsets.
- **`onPrimaryTap`** = LMB click (both modes). **`onSecondaryTap`** = RMB click (UI only). **`onHoldStart`/`onHoldEnd`** = LMB down/up (in-game chain hold AND UI "tap-then-slide-press"). **`onSecondaryHoldStart`/`onSecondaryHoldEnd`** = RMB down/up (UI "double-tap-then-slide-press").
- **Mode change resets the lookpad gesture FSM** so a mid-gesture mode flip can't strand state.
- **`ButtonRouter.ReleaseAll()`** fires on disconnect AND on flip to `AntiMistouch`, preventing stuck keys.
- **In-game and UI mode are toggled via per-widget `visibility = GONE`**, NOT wrapper LinearLayouts. (We dropped the wrappers so multi-touch split-touch works across widgets.)
- **Each editable widget is at the FrameLayout root** (not nested), again for clean multi-touch.
- **i18n on the WinUI 3 side** goes through `McController.App.Util.L`: dotted-key lookups with hard-coded Simplified Chinese + English dictionaries, picked once at startup from `CultureInfo.CurrentUICulture`. We skipped `.resw` + `x:Uid` because the MRT pipeline is annoying for unpackaged WinUI 3 with only two languages.
- **Window-chrome tint brushes** are owned and mutated by `MainWindow` (`_chromeBrush`, `_contentBrush`); the GlobalSettings page edits `AppearancePreferences`, which raises a `Changed` event that flips `Opacity` on those brushes. Don't rebuild the brushes per change — opacity edits on the same instance redraw fine.

## Caveats to remember

- **PC server holds its EXE open** — building fails if the previous run is still active. Use `Stop-Process -Name McController.App -Force` before rebuild.
- **WinUI 3 builds via MSBuild, not `dotnet build`** — the `Pri.Tasks.dll` pack steps need the Windows App SDK MSBuild integration that ships with VS Build Tools' "Windows App SDK C# Templates" workload. `dotnet build` works for the Core library + tests, but for the App project use the VS Build Tools' `MSBuild.exe` (path in `installer/README.md`).
- **`adb reverse` is TCP-only**. UDP fallback is the `LOOK_DELTA_TCP` message variant.
- **Old saved profiles** may reference dropped widget IDs (`row_top_buttons`, `column_ui_buttons`, `row_sneak_sprint`). `ProfileStore.parseModeLayout` falls back to `DefaultLayouts` for missing keys, so things still work, but the user should hit "Reset Layout" in the editor to pick up new positions.
- **Don't reintroduce `setLayerType(LAYER_TYPE_SOFTWARE)` for non-shadow views** — it affects rendering perf and has caused subtle issues with `View.foreground` selection rings.
- **IME auto-switch (en-US layout)** is currently disabled in App startup because `PostMessage(WM_INPUTLANGCHANGEREQUEST)` causes MC to briefly release/regrab the cursor, which the mode monitor mis-reads. Code is in `InputLanguageManager.cs` waiting for a less-intrusive re-enable path.

## Build sanity (1-liners)

```powershell
# Core library + tests (plain dotnet, fast)
dotnet build  E:\dev\personal\mc_controller\pc\McController.Core\McController.Core.csproj
dotnet test   E:\dev\personal\mc_controller\pc\McController.Core.Tests\McController.Core.Tests.csproj

# WinUI 3 app — uses VS Build Tools' MSBuild (Windows App SDK targets)
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    E:\dev\personal\mc_controller\pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64

# Run the app
Start-Process E:\dev\personal\mc_controller\pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe

# SendInput self-test (Core has a CLI entry behind `--selftest`; wired through App's Program.Main)
& <app-exe> --selftest

# Installer (after a Release publish)
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" E:\dev\personal\mc_controller\installer\McController.iss

# Android
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb reverse tcp:34555 tcp:34555                                          # USB mode
```

See [docs/development.md](docs/development.md) for the full workflow including common errors and their fixes.

## Status snapshot (when picking up)

See `## Implementation status` in [docs/architecture.md](docs/architecture.md). Recent / in-progress:

- **Distribution-ready** ✅ — Inno Setup installer; `%APPDATA%` config; tray + hide-to-tray; footer pages (全局设置 / 关于); i18n (ZH/EN); LAN announce + PROBE protocol; ADB auto-reverse on device connect.
- **Window transparency prefs** ✅ — Global Settings → 外观 has a master switch + sidebar/title-bar opacity slider + content-area opacity slider. Persists to `appearance.json`.
- **HotbarSwipeMode** (`core/LayoutSpec.kt`): new enum `{ Precise, Relative }`. Stored on `LayoutProfile`. `HotbarView.swipeMode` reads it. Relative mode: ~32 dp horizontal travel cycles one slot, wraps 0 ↔ 8. **WIP — not yet wired to profile editor UI.**
- **Step 12** (PC auto-`adb reverse` for any connected device): ✅ done (`AdbDiscovery` fires `adb reverse` on detect, dedup'd by serial).
- **Step 13**: Latency visualization polish — P50/P99 RTT, UDP loss rate, HUD packet counters. Pending.
- **iOS + macOS migration**: see [docs/porting.md](docs/porting.md). Not started; project structure already isolates the platform-specific bits into `McController.App` and a handful of files inside `McController.Core` (`Win32InputInjector`, `CursorInjector`, `WindowStateMonitor`, `InputLanguageManager`, `PrecisionTimer`), which is the natural cleavage plane.

User-driven UX iteration is ongoing — feel is tuned by editing tunables in `JoystickView` / `LookPadView` / `ActionButtonView` and via the in-app Layout Editor.
