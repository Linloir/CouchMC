# CLAUDE.md — AI Agent Orientation

This file is the first thing an AI coding agent should read when picking up work on this project. It points to the canonical docs and summarizes context that's stable across sessions.

## The 10-second pitch

Turn an Android phone into a touchscreen controller for PC Java Edition Minecraft. Phone runs a Kotlin app that captures touch (joystick + look pad + buttons) and streams input events to a Windows `.NET 8 + WinForms` server that injects keyboard/mouse via `SendInput`.

The **key architectural insight** is the 3-state mode system: instead of mirroring MC's inventory/menu UIs over the wire, the PC detects MC's window+cursor state (`WindowStateMonitor`) and tells the phone which mode to render — in-game (full controller), UI-interact (lookpad drives cursor + small button set), or anti-mistouch (lock screen).

## Canonical docs (in order)

1. **[docs/architecture.md](docs/architecture.md)** — design rationale, module map, decision log
2. **[docs/development.md](docs/development.md)** — build / install / debug workflow, common pitfalls
3. **[docs/protocol.md](docs/protocol.md)** — wire protocol (single source of truth for PC/Android codecs)
4. **[README.md](README.md)** — user-facing prerequisites + quick start

The plan file at `~/.claude/plans/app-mc-zesty-starlight.md` is **not portable across machines** — treat docs/architecture.md as authoritative.

## Layout

```
mc_controller/
├── pc/                              .NET 8 WinForms solution
│   ├── McController.sln
│   ├── McController.Server/         the server itself
│   └── McController.Server.Tests/   xUnit, 40 tests
├── android/                         Gradle / Kotlin Android app
│   ├── settings.gradle.kts
│   └── app/src/main/...
├── docs/                            spec + design + workflow
└── tools/                           helper scripts
```

## Key technical facts

- **PC language**: C# / .NET 8, console + WinForms (`<UseWindowsForms>true</UseWindowsForms>`, `<OutputType>Exe</OutputType>`). Console window + tuning Form coexist for demo phase.
- **Android language**: Kotlin 1.9.22, AGP 8.2.2, min SDK 26, target 34, view binding.
- **Transport**: TCP for control + UDP for camera deltas (WiFi only — USB mode via `adb reverse` is TCP-only, with `LOOK_DELTA_TCP` fallback).
- **Wire frame**: length-prefixed binary, big-endian. Camera deltas are in tenths-of-pixel (`SUBPIXEL_SCALE = 10` on both ends).
- **Default port**: 34555.
- **Mode detection**: `WindowStateMonitor` polls `GetForegroundWindow()` + `GetCursorInfo()` every 100 ms with 1-tick debounce.
- **Cursor driving in UI mode**: `SetCursorPos` clamped to MC client rect (no global `ClipCursor`).
- **WASD mapping**: `JoystickToWasdMapper` with dead-zone, enter/exit hysteresis, and `<=` comparison for release (so `0` everywhere still releases — regression-tested).
- **Sub-pixel residuals**: `LookPadView`, `ActionButtonView` (HOLD-mode drag), `CameraCurve` all carry fractional remainders across calls.
- **Gesture FSM** for `LookPadView`: hand-rolled (not `GestureDetector`), ~10 states. In-game: zero-latency tap + chained LMB-held via double-press. UI mode: 200 ms wait for single-tap; double-tap → RMB; "tap + re-press + slide" → LMB hold; "double-tap + re-press + slide" → RMB hold. State resets on mode change (releases any held button).
- **Layout system**: every editable widget is described by a `WidgetSpec(anchor, edge, vert, w, h)`; `LayoutApplier` writes margins/gravity onto `FrameLayout.LayoutParams`. Profiles persisted in SharedPreferences as JSON.

## Conventions

- **Wire deltas are tenths-of-pixel** (×10 from finger px). Android scales up, PC scales down.
- **Joystick output** is fixed-point i16 with scale 10000 (so `0.5f` → `5000`).
- **`Anchor.BottomCenter` / `TopCenter`** ignore `edgeMarginDp` (horizontal always centered) and global L/R offsets.
- **`onPrimaryTap`** = LMB click (both modes). **`onSecondaryTap`** = RMB click (UI only). **`onHoldStart`/`onHoldEnd`** = LMB down/up (in-game chain hold AND UI "tap-then-slide-press"). **`onSecondaryHoldStart`/`onSecondaryHoldEnd`** = RMB down/up (UI "double-tap-then-slide-press").
- **Mode change resets the lookpad gesture FSM** so a mid-gesture mode flip can't strand state.
- **`ButtonRouter.ReleaseAll()`** fires on disconnect AND on flip to `AntiMistouch`, preventing stuck keys.
- **In-game and UI mode are toggled via per-widget `visibility = GONE`**, NOT wrapper LinearLayouts. (We dropped the wrappers so multi-touch split-touch works across widgets.)
- **Each editable widget is at the FrameLayout root** (not nested), again for clean multi-touch.

## Caveats to remember

- **PC server holds its EXE open** — `dotnet build` fails if the previous run is still active. Use `Stop-Process -Name McController.Server -Force` before rebuild.
- **`adb reverse` is TCP-only**. UDP fallback is the `LOOK_DELTA_TCP` message variant.
- **Old saved profiles** may reference dropped widget IDs (`row_top_buttons`, `column_ui_buttons`, `row_sneak_sprint`). `ProfileStore.parseModeLayout` falls back to `DefaultLayouts` for missing keys, so things still work, but the user should hit "Reset Layout" in the editor to pick up new positions.
- **Don't reintroduce `setLayerType(LAYER_TYPE_SOFTWARE)` for non-shadow views** — it affects rendering perf and has caused subtle issues with `View.foreground` selection rings.
- **IME auto-switch (en-US layout)** is currently disabled in Program.cs because `PostMessage(WM_INPUTLANGCHANGEREQUEST)` causes MC to briefly release/regrab the cursor, which the mode monitor mis-reads. Code is in `InputLanguageManager.cs` waiting for a less-intrusive re-enable path.

## Build sanity (1-liners)

```powershell
# PC
dotnet build E:\dev\personal\mc_controller\pc\McController.sln
dotnet test  E:\dev\personal\mc_controller\pc\McController.sln           # 40 tests
dotnet run   --project E:\dev\personal\mc_controller\pc\McController.Server
dotnet run   --project ... --selftest                                    # SendInput validation

# Android
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb reverse tcp:34555 tcp:34555                                          # USB mode
```

See [docs/development.md](docs/development.md) for the full workflow including common errors and their fixes.

## Status snapshot (when picking up)

See `## Implementation status` in [docs/architecture.md](docs/architecture.md). Recent / in-progress:

- **HotbarSwipeMode** (`core/LayoutSpec.kt`): new enum `{ Precise, Relative }`. Stored on `LayoutProfile`. `HotbarView.swipeMode` reads it. Relative mode: ~32dp horizontal travel cycles one slot, wraps 0 ↔ 8 — replaces dispatching `HOTBAR_N` per slot crossed. **WIP — not yet wired to ButtonRouter/profile editor UI.**
- **Step 12**: PC server auto-runs `adb reverse` on launch + Android "USB connect" button auto-fills 127.0.0.1. Pending.
- **Step 13**: Latency visualization polish — Form P50/P99 RTT, UDP loss rate, HUD packet counters. Pending.

User-driven UX iteration is ongoing — feel is tuned by editing tunables in `JoystickView` / `LookPadView` / `ActionButtonView` and via the in-app Layout Editor.
