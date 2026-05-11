# Architecture

> The authoritative design + implementation reference. Update this when major decisions change.

## 1. Problem statement

Traditional gamepads handle PC Minecraft poorly because the right stick is a bad camera control — too slow for combat, too imprecise for placement. Mobile MC solved this with a touch joystick + look-pad-style swipe area, and **the user wants that exact feel on PC MC, from the couch**.

The solution is to make a phone act as a touchscreen-native controller for PC MC. The phone runs a custom Kotlin app, the PC runs a .NET 8 server that translates input packets into native keyboard/mouse events.

## 2. The 3-state mode system (the key insight)

Trying to mirror MC's inventory/chest/crafting UIs over the wire would require a custom mod and a ton of UI work. The simpler insight: **let the user interact with MC's own UIs by driving the system cursor instead of building parallel UIs on the phone**.

PC-side, `WindowStateMonitor` polls the foreground window + cursor visibility every 100ms (1-tick debounce). It maps that to one of three modes:

| Mode | Detection | Phone UI | Server LOOK_DELTA routing |
|---|---|---|---|
| `InGame` (0) | MC focused + GLFW cursor captured (`CURSORINFO.flags == 0`) | Full controller — joystick + LookPad + arc-fan buttons + hotbar | `SendInput(MOUSEEVENTF_MOVE)` relative — feeds raw input |
| `UiInteract` (1) | MC focused + cursor visible | LookPad drives cursor; 5 reduced buttons (LMB/RMB/Esc/Q/Shift) | `SetCursorPos` clamped to MC client rect |
| `AntiMistouch` (2) | MC not foreground | Full-screen lock overlay; touches blocked | LOOK packets dropped server-side |

Server pushes `STATE_CHANGE` on every detected transition; phone mirrors via `ControllerSession.mode: StateFlow<ControllerMode>`. The phone resets its gesture FSM on mode flips so a finger that lands during in-game and lifts during UI-mode can't strand state.

Why this works: from MC's perspective, every input is a normal mouse/keyboard event — no mod needed. The phone reshapes its UI to match what the PC is doing.

## 3. Transport

```
Android client                                  PC server
  │                                               │
  ├── TCP (control: HELLO, JOYSTICK, BUTTON,      │
  │       LOOK_DELTA_TCP fallback, PING)          │
  │       length-prefixed binary, NoDelay=true ───┤
  │                                               │
  ├── UDP (camera: LOOK_DELTA, WiFi only) ────────┤
  │       seq-based dedup, drops on reorder       │
  │                                               │
  │ ◄── STATE_CHANGE, HELLO_ACK, PONG (TCP) ──────┤
```

- **TCP** for everything except camera deltas in WiFi mode. Control packets must arrive reliably and in order (a missed BUTTON down-edge is bad). `TCP_NODELAY=true` to skip Nagle.
- **UDP** for `LOOK_DELTA` over WiFi: ≤125 Hz, lossy-OK (next packet's delta naturally compensates), avoids TCP head-of-line blocking. Server tracks a per-session `lastSeq` and drops anything with `seq <= lastSeq`.
- **USB mode** falls back to TCP for everything because `adb reverse` doesn't forward UDP. Client sends `wantsUdp=0` in HELLO; server replies `udpPort=0`; camera deltas use `LOOK_DELTA_TCP` (same payload + seq, just length-prefixed in the TCP framing).
- **Sub-pixel scaling**: wire camera deltas are in tenths-of-pixel (Android multiplies by `SUBPIXEL_SCALE = 10` before sending; PC divides by the same). Lets micro-aim register without inflating the i16 range.

See [protocol.md](protocol.md) for the full byte-level spec.

## 4. Android module map

```
android/app/src/main/java/com/mccontroller/
├── core/
│   ├── ControllerSession.kt      Lifecycle: connect, ping loop, mode mirror,
│   │                             RTT measurement, send helpers, disconnect()
│   ├── ControllerMode.kt         enum: InGame / UiInteract / AntiMistouch
│   ├── LayoutSpec.kt             WidgetSpec / ModeLayout / LayoutProfile data;
│   │                             DefaultLayouts.IN_GAME and UI_MODE
│   ├── ProfileStore.kt           JSON-in-SharedPreferences; load/save/setActive
│   └── LayoutApplier.kt          Writes margins/gravity onto FrameLayout.LayoutParams
│
├── net/
│   ├── Protocol.kt               MsgType / HelloAckStatus / ControllerMode /
│   │                             ButtonId constants — MIRROR of PC's Protocol.cs
│   ├── Messages.kt               sealed ControlMessage hierarchy
│   ├── PacketCodec.kt            encode/decode (TCP frames + UDP datagrams)
│   ├── TcpChannel.kt             Socket wrapper, runReadLoop emits to callback
│   ├── UdpChannel.kt             DatagramSocket wrapper, auto-increments seq
│   └── HybridTransport.kt        TCP+UDP coordinator + handshake;
│                                 serverMode: StateFlow<Byte> captured eagerly
│
├── input/
│   └── LookAccumulator.kt        AtomicInteger pair, flushes every 8ms (~125Hz)
│
└── ui/
    ├── ConnectActivity.kt        IP/port input, profile picker, "Edit Layout"
    ├── ControllerActivity.kt     Game surface: layout apply, gesture wiring,
    │                             volume-key intercept, HUD, mode-driven visibility
    ├── LayoutEditorActivity.kt   Full-screen canvas + floating toolbar +
    │                             selection model (tap=select, drag=move,
    │                             pinch-anywhere=resize-selected)
    └── view/
        ├── JoystickView.kt       Dynamic (floating) joystick; emits raw [-1,1] +
        │                         sprint-engage edge on past-rim radius
        ├── LookPadView.kt        Touch surface; custom gesture FSM (taps + hold);
        │                         sub-pixel residual; isDragging exposed
        ├── ActionButtonView.kt   Generic round button: HOLD/TOGGLE/TAP modes,
        │                         optional drag-while-held delta (for LMB/RMB)
        ├── HotbarView.kt         9 slots; tap=select, long-press=drop loop,
        │                         swipe=switch; slotAt clamps to extremes
        └── EditorCanvas.kt       Editor-only FrameLayout that intercepts
                                  multi-touch for pinch-resize-anywhere
```

### Phone-side specifics worth knowing

- **All editable widgets are direct children of the FrameLayout root** (no wrapper LinearLayouts). This is required for `splitMotionEvents` to actually split — wrapping joystick + LookPad under one ViewGroup caused multi-touch to break.
- **Visibility** is toggled per-widget via `ControllerActivity.updateLayerVisibility(mode)` — there's `inGameWidgets` and `uiModeWidgets` lists.
- **The joystick is intentionally non-editable** in the layout editor (its activation zone is large and moving it doesn't help). Filtered out in `LayoutEditorActivity.attachWidgetEditListeners()`.
- **Gesture FSM in LookPadView** has ~10 states and is **mode-aware**:
  - Shared: `IDLE`, `PRIMED1`, `DRAG`
  - In-game: `AFTER_TAP`, `LMB_HELD_INGAME`
  - UI mode: `SINGLE_PENDING`, `SECOND_PRIMED`, `LMB_HELD_UI`, `DOUBLE_PENDING`, `THIRD_PRIMED`, `RMB_HELD`
  - In-game fires taps immediately on UP. UI mode waits 200 ms to disambiguate single-vs-double. Additional UI branches: "tap + re-press + slide" → LMB held during slide (`onHoldStart`/`End`); "double-tap + re-press + slide" → RMB held during slide (`onSecondaryHoldStart`/`End`).
  - `slidDuringHold` tracks whether the held finger crossed `touchSlop`. If a held block ended without sliding, FSM chains back to `AFTER_TAP`; if it slid, FSM ends at `IDLE` so the next press is a fresh first tap.
- **Hotbar slot conflation** for fast swipes: `ControllerActivity.hotbarSelectChannel: Channel<Int>(CONFLATED)` + single sender coroutine ensures the latest slot wins on rapid swipes.
- **Hotbar swipe mode** (`HotbarSwipeMode.Precise` vs `Relative`) is stored on `LayoutProfile` and read by `HotbarView.swipeMode`. Precise = absolute slot under finger (clamp at edges). Relative = scroll-wheel feel, ~32 dp horizontal travel per slot cycle, wraps at 0 ↔ 8. **In progress: profile editor UI / ButtonRouter integration not fully wired yet.**
- **Volume keys** are intercepted in `ControllerActivity.onKeyDown/onKeyUp` and routed to MOUSE_LEFT / MOUSE_RIGHT. Auto-repeat events are filtered. Returning `true` suppresses the system volume UI.

## 5. PC module map

```
pc/McController.Server/
├── Program.cs                    Top-level entrypoint, wires everything;
│                                 `--selftest` arg runs Diag/SelfTest
├── Net/
│   ├── Protocol.cs               MsgType / HelloAckStatus / ControllerMode /
│   │                             ButtonId constants — MIRROR of Android's
│   ├── Messages.cs               record ControlMessage hierarchy
│   ├── PacketCodec.cs            EncodeXxx + TryReadFrame + TryParseUdp
│   ├── TcpServer.cs              Single-client listener; events fired on
│   │                             read-loop thread; sync ProcessAndCompact
│   │                             helper because async can't hold ref-struct
│   │                             locals in C# 12
│   └── UdpServer.cs              UdpClient + per-client seq dedup
│
├── Input/
│   ├── IInputInjector.cs         interface (for FakeInjector in tests)
│   ├── Win32InputInjector.cs     SendInput P/Invoke (relative mouse, scancodes)
│   ├── Scancodes.cs              Windows scancode constants (W/A/S/D/Space/...)
│   ├── JoystickToWasdMapper.cs   Dead zone + enter/exit hysteresis;
│   │                             uses `<=` so abs=0 always releases
│   ├── ButtonRouter.cs           Resolves Bindings → key/mouse actions;
│   │                             tracks _down for ReleaseAll
│   ├── CameraCurve.cs            Sensitivity × accel (Linear or Power);
│   │                             residual carry-over; takes float now
│   ├── CursorInjector.cs         SetCursorPos clamped to MC client rect
│   └── InputLanguageManager.cs   LoadKeyboardLayout("00000409") +
│                                 PostMessage(WM_INPUTLANGCHANGEREQUEST);
│                                 currently NOT wired (see caveats)
│
├── Config/
│   ├── ServerConfig.cs           Port + Camera + Movement + Bindings
│   └── ConfigStore.cs            System.Text.Json load/save with camelCase
│
├── Diag/
│   ├── WindowStateMonitor.cs     100 ms poll loop, 1-tick debounce,
│   │                             exposes CurrentMode + CurrentClientRect
│   ├── ConnectionStats.cs        Atomic counters + RTT window
│   ├── PrecisionTimer.cs         timeBeginPeriod(1) + PreciseSleep
│   │                             (only used by SelfTest)
│   └── SelfTest.cs               Step 1 validation routine for SendInput
│
└── Tuner/
    └── TuningForm.cs             WinForms sliders + status panel;
                                  live-edits ServerConfig (atomic field reads)
```

### PC-side specifics worth knowing

- **Top-level program** drives everything from `Program.cs`. The `[STAThread]` is implicit because `<UseWindowsForms>true</UseWindowsForms>` adds it.
- **Outputs `Exe` (not WinExe)** so a console window stays open alongside the Form. Demo-mode convenience; switch to WinExe + in-form log view for production.
- **Mapper / Curve / Router** all share a reference to `ServerConfig`. The TuningForm slider's `ValueChanged` mutates ServerConfig in place; atomic float/enum reads make this lock-free.
- **CameraCurve takes float** as of the SUBPIXEL_SCALE change — `Apply(float, float) → (int sdx, int sdy)`. Existing tests still pass because integer args auto-widen.
- **WindowStateMonitor.OnModeChanged** fires the `STATE_CHANGE` push + clears held buttons on AntiMistouch.
- **InputLanguageManager.EnsureEnglishLayout()** exists but is disabled — `PostMessage(WM_INPUTLANGCHANGEREQUEST)` causes MC to briefly toggle cursor capture, which the monitor mis-reads. Reintroduce via a non-foreground-disrupting path.
- **PC server holds its own `.exe` open** while running; rebuilding requires killing the process first (`Stop-Process -Name McController.Server -Force`).

## 6. Wire protocol summary

(Full spec in [protocol.md](protocol.md).)

- **TCP frame**: `[u16 len BE][u8 type][payload]` where `len` counts type+payload.
- **UDP datagram**: `[u8 type][u32 seq BE][payload]`.
- All multi-byte fields big-endian.
- Message types:
  - `0x01` HELLO (C→S): `u8 protoVer, u32 clientId, u8 wantsUdp`
  - `0x02` HELLO_ACK (S→C): `u8 status, u16 udpPort`
  - `0x03` STATE_CHANGE (S→C): `u8 mode` (0/1/2)
  - `0x10` JOYSTICK (C→S): `i16 x, i16 y` (fixed-point ×10000, range ±10000)
  - `0x11` LOOK_DELTA (C→S, UDP): `u32 seq, i16 dx, i16 dy` in **tenths-of-pixel**
  - `0x11` LOOK_DELTA_TCP (C→S, TCP fallback): same payload but inside the length-prefixed frame
  - `0x20` BUTTON (C→S): `u8 buttonId, u8 down`
  - `0xF0` PING (C→S): `u32 seq`
  - `0xF1` PONG (S→C): `u32 seq` (echoes ping)

ButtonIds: `0x01` MOUSE_LEFT, `0x02` MOUSE_RIGHT, `0x10` JUMP (Space), `0x11` SNEAK (LShift), `0x12` SPRINT (LCtrl), `0x20` INVENTORY (E), `0x21` DROP (Q), `0x22` SWAP_HAND (F), `0x30` ESC, `0x40..0x48` HOTBAR_1..9 (1..9 keys).

## 7. Design decisions (with rationale)

### Native Kotlin + .NET 8, not Flutter / Tauri / web
- Touch input latency budget is single-digit ms. Both ends call straight to OS primitives (`MotionEvent` / `SendInput`). Cross-platform UI frameworks add 1-3 frames per side and weren't worth it.

### TCP + UDP split, not pure UDP
- Control packets (HELLO, BUTTON, JOYSTICK normalized position) need ordering and reliable delivery — a dropped BUTTON down-edge stays pressed forever. Camera deltas can drop freely (next swipe re-supplies position). The split is the natural fit.

### Wire deltas in tenths-of-pixel (`×10` scaling)
- Slow micro-aim moves <1 px/sample on the phone. Truncating to int kills precision. Multiplying by 10 before encode + carrying a fractional residual on both ends preserves fine aim. i16 range still allows ±3276 px/packet which is plenty.

### Hand-rolled gesture FSM in LookPadView, not GestureDetector
- `GestureDetector.onSingleTapConfirmed` waits ~300 ms for a potential double-tap, killing rapid-click feel in-game. Our FSM fires the in-game tap immediately on UP and only delays the UI-mode tap (which genuinely must distinguish from RMB-on-double-tap), with a tightened 200 ms window.
- In-game double-tap → second DOWN immediately fires `onHoldStart` (LMB down) and the FSM transitions to `LMB_HELD`. Releasing chains back to `AFTER_TAP` so a third tap can start another held block.

### Anchor-based layout (`Anchor.BottomEnd` etc.), not absolute coordinates
- Profiles persist as small `WidgetSpec(anchor, edge, vert, w, h)` records that survive screen-size differences. `LayoutApplier` translates to `FrameLayout.LayoutParams` margins + gravity at apply time.
- `BottomCenter` / `TopCenter` anchors ignore `edgeMarginDp` (always horizontally centered) and the global L/R offsets — used for the hotbar.

### Selection-based editing in LayoutEditorActivity
- Original "single-finger drag = move, two-finger pinch on widget = resize" forced users to pinch precisely on the small button. Selection model decouples: tap to select (yellow ring via `View.foreground`), drag to move, **pinch anywhere on canvas** to resize the selected widget. Empty-canvas tap deselects.
- `EditorCanvas` (custom FrameLayout) overrides `onInterceptTouchEvent` to grab two-finger gestures so widget single-finger drag and canvas pinch don't fight.

### Dead-zone-safe release in JoystickToWasdMapper
- Original `<` comparison: with all thresholds at 0, a release event (`abs == 0`) failed `abs < 0`, so the held key never released ("stuck A" bug). Fix was `<=` for dead-zone AND exit-threshold checks. Regression test in `JoystickToWasdMapperTests.AllThresholdsZero_ReleaseAtZero_StillReleases`.

### Sprint engages by pushing past the rim
- The joystick has a base radius; pushing **further** triggers sprint. Equal engage/disengage radius (`1.2 × baseRadius`) per user feedback — no hysteresis band. Sprint state is OR-combined with the toggle button: either source held = SPRINT pressed on PC, and the toggle button's visual is synced to the effective state via `setToggleState`.

### Profile JSON in SharedPreferences (single blob)
- Five fields per widget, ~10 widgets per mode, 2 modes per profile, plus name → a few KB even with many profiles. No need for a real DB. JSON gives easy schema evolution (new keys absorbed by `parseModeLayout` fallback).

## 8. Implementation status

Steps refer to the original plan file (`~/.claude/plans/app-mc-zesty-starlight.md`, not committed). Numbering preserved for traceability.

**Done:**
- Step 0 — Repo init (.gitignore, README, docs/protocol.md)
- Step 1 — PC SendInput validation at 125 Hz (`Diag/SelfTest.cs`)
- Step 2 — TCP + UDP server + protocol codec + 40 unit tests
- Step 3 — WinForms TuningForm with live config sliders
- Step 4 — Android Connect screen + HELLO/HELLO_ACK + PING/PONG RTT + HUD
- Step 5 — JoystickView (dynamic) → WASD over TCP, with deadzone+hysteresis
- Step 6 — LookPadView + LookAccumulator (8 ms flush) over UDP (TCP fallback in USB)
- Step 7 — ActionButtonView + HotbarView baseline + 8 in-game buttons
- Step 8 — 3-state mode system (`WindowStateMonitor` + `STATE_CHANGE` + cursor injector + Android UI switching) + 6 UX bug fixes (multi-touch split, hotbar swipe-vs-drop disambiguation, UI buttons on left, joystick sprint extension, sub-pixel LookPad residual, fan-layout right cluster)
- Step 14 — Layout editor: drag/pinch/L-R-margin, multi-profile, full-screen canvas + floating toolbar + selection model

**Follow-ups landed (post-Step-8/14):**
- Reconnect mode-stale fix (`HybridTransport.serverMode: StateFlow<Byte>`)
- Volume-key intercept (VOL_UP/DOWN → LMB/RMB)
- Hotbar conflation channel (`Channel.CONFLATED` + single sender)
- Hotbar slot clamp (out-of-bounds swipe → extreme slot)
- Symmetric sprint threshold (1.2 / 1.2)
- Sprint button visual mirrors effective state
- ×10 wire sub-pixel precision for LOOK_DELTA
- Editor selection model (joystick non-editable; rows decomposed into individual buttons)
- BottomCenter anchor for hotbar (no overlap with right-side fan)
- LMB/RMB drag-while-held nudges camera (gated by `LookPad.isDragging`)
- Custom gesture FSM (zero-latency in-game taps + chained LMB hold; 200 ms UI double-tap window)
- en-US keyboard layout helper (built; **not currently wired** — see caveats)

**In progress / pending:**
- **Hotbar swipe modes (~Step 11)**: `HotbarSwipeMode` enum added to `LayoutSpec`. `HotbarView.swipeMode` field present. `Relative` mode logic in HotbarView is partial — accumulator + 32 dp threshold scroll-wheel-style cycling with wrap. **Outstanding: hook through `LayoutProfile.hotbarSwipeMode`, expose toggle in the editor UI, possibly tune the per-step distance.**
- **Step 12**: USB-mode auto-config. PC server starts `adb reverse tcp:34555 tcp:34555` on launch (best-effort; warn if `adb` missing). Android "Connect (USB)" button auto-fills 127.0.0.1.
- **Step 13**: Latency visualization polish. Form shows P50/P99 RTT, UDP loss rate (computed from seq gaps), per-second packet counts. Android HUD shows the same.

## 9. Caveats / gotchas

| Item | What to remember |
|---|---|
| PC build fails with file-lock error | Server process holds `McController.Server.exe` open. `Stop-Process -Name McController.Server -Force` (PowerShell) before rebuild. |
| `adb reverse` doesn't support UDP | USB mode uses `LOOK_DELTA_TCP` automatically. Tested. |
| `MutableSharedFlow(replay = 0)` swallows pre-subscribe emissions | The mode bug after reconnect was caused by this. Fix: `HybridTransport.serverMode` is a `StateFlow` (always replays current value) — read-loop writes directly. |
| Mid-gesture mode flip | `LookPadView.mode` setter calls `resetGestureState()` to release any held LMB and clear timers. |
| Auto-IME-switch is **disabled** | `PostMessage(WM_INPUTLANGCHANGEREQUEST)` to MC's HWND causes MC to flicker cursor capture state, which the monitor mis-reads. `InputLanguageManager` code is kept; re-enable via a non-disruptive path (e.g., once on HELLO_ACK only, or with a config flag). |
| `setLayerType(LAYER_TYPE_SOFTWARE)` | Required for `setShadowLayer` / `BlurMaskFilter` to render reliably on API 26+, but can interact subtly with `View.foreground`. Used on JoystickView and ActionButtonView. |
| Old saved profiles | Reference dropped widget IDs (`row_top_buttons`, `column_ui_buttons`, `row_sneak_sprint`). `ProfileStore.parseModeLayout` fills missing keys from `DefaultLayouts`, but the user should hit "Reset Layout" once to pick up new defaults. |
| `LF/CRLF` git warnings on Windows | Expected. `core.autocrlf` not configured project-wide; warnings during `git add` are noise. |
| Top-level Kotlin `null` for callbacks | Lots of `var onFoo: (() -> Unit)?`. Pattern is `onFoo?.invoke()` at the call site. Don't be tempted to make them lateinit. |
| C# 12 ref-struct in async | `TryReadFrame(Span<byte>...)` can't be called from an `async` body. The `TcpServer.RunReadLoop` splits the synchronous span-using code into a separate helper. |
| Existing PC tests | 40 tests in `McController.Server.Tests/`. `JoystickToWasdMapperTests` has a regression test for the stuck-key bug (search `AllThresholdsZero_ReleaseAtZero_StillReleases`). Keep this green. |
