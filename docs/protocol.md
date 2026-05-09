# MC Controller — Wire Protocol

This document is the **single source of truth** for the over-the-wire protocol between the Android client and the Windows PC server. PC and Android implementations of `PacketCodec` and `Protocol` constants must mirror this spec.

All multi-byte integer fields are **big-endian**.

## Transport overview

| Channel | Carrier | Used for |
|---|---|---|
| TCP | Single connection, `TCP_NODELAY=true` | HELLO, JOYSTICK, BUTTON, PING/PONG, LOOK_DELTA fallback |
| UDP | Optional, WiFi-only, opened after HELLO_ACK | LOOK_DELTA (high-frequency, lossy-OK) |

In **USB mode** (the Android client connects via `127.0.0.1` after the host runs `adb reverse tcp:34555 tcp:34555`), UDP is NOT available — `adb reverse` only forwards TCP. The client signals `wantsUdp=0` in HELLO and the server responds with `udpPort=0`. All packets, including LOOK_DELTA, are sent over TCP using the `LOOK_DELTA_TCP` message variant.

## TCP frame format

```
+---------+----------+--------------------+
| u16 len | u8  type | payload (len-1 B)  |
+---------+----------+--------------------+
   2B        1B          0..N B
```

- `len` is the count of bytes from the `type` byte onward (i.e., includes the type byte itself).
- The minimum frame is `len=1` (a type byte with no payload).
- Both peers should use a 4 KiB read buffer and a `TryReadFrame` style decoder.

## UDP datagram format

```
+--------+---------+----------+
| u8 type| u32 seq | payload  |
+--------+---------+----------+
   1B       4B       0..N B
```

- The datagram boundary itself defines packet length — no length prefix.
- `seq` is monotonically increasing, starting at 0 for each new session.
- Currently only `LOOK_DELTA` (type `0x11`) uses UDP.

## TCP messages (control channel)

| Type | Name | Payload | Direction | Frequency |
|---|---|---|---|---|
| `0x01` | `HELLO` | `u8 protoVer, u32 clientId, u8 wantsUdp` | C→S | 1× per session |
| `0x02` | `HELLO_ACK` | `u8 status, u16 udpPort` | S→C | 1× per session |
| `0x03` | `STATE_CHANGE` | `u8 mode` (0=InGame, 1=UiInteract, 2=AntiMistouch) | S→C | on connect + on mode change |
| `0x10` | `JOYSTICK` | `i16 x, i16 y` (fixed-point: actual value × 10000, range ±10000) | C→S | throttled, ≤ 60 Hz |
| `0x11` | `LOOK_DELTA_TCP` | `u32 seq, i16 dx, i16 dy` | C→S | ~125 Hz (USB / UDP fallback only) |
| `0x20` | `BUTTON` | `u8 buttonId, u8 down` (0 = up, 1 = down) | C→S | edge-triggered |
| `0xF0` | `PING` | `u32 seqNum` | C→S | 1 Hz |
| `0xF1` | `PONG` | `u32 seqNum` (echoes the PING seqNum) | S→C | immediate |

### STATE_CHANGE semantics

The PC server polls the foreground window + cursor visibility every 100ms
(with 1-tick debounce) and pushes a `STATE_CHANGE` whenever the derived
mode changes. The first `STATE_CHANGE` is sent immediately after `HELLO_ACK`
so the client can render the correct initial UI.

| mode | Server detects | Client UI | Server LOOK routing |
|---|---|---|---|
| 0 InGame | MC focused + GLFW cursor captured (`CURSORINFO.flags == 0`) | Full controller (joystick + buttons + hotbar) | `SendInput(MOUSEEVENTF_MOVE)` relative |
| 1 UiInteract | MC focused + cursor visible | LookPad drives cursor; reduced button set (LMB/RMB/Esc/Q/Shift) | `SetCursorPos` clamped to MC client rect |
| 2 AntiMistouch | MC not in foreground | Full-screen lock overlay; touches blocked | LOOK packets dropped server-side |

### HELLO_ACK status codes
- `0` — OK, connection accepted
- `1` — protocol version mismatch
- `2` — server busy / already has a client (demo: single-client only)

### HELLO_ACK udpPort
- Non-zero — server has a UDP listener bound; client should open UDP and send LOOK_DELTA there
- Zero — server does not accept UDP (or this is USB mode); client should send `LOOK_DELTA_TCP` over TCP instead

### JOYSTICK fixed-point encoding
- Wire value is `actual × 10000` clamped to `[-10000, 10000]`
- Decoded as `wireValue / 10000.0f`
- Convention: `y > 0` means **forward** (Android flips screen-Y)
- Client must always send `JOYSTICK(0, 0)` on stick release as a safety net

## UDP messages (camera channel)

| Type | Name | Payload | Direction |
|---|---|---|---|
| `0x11` | `LOOK_DELTA` | `i16 dx, i16 dy` (the `seq` is in the common header) | C→S |

### Server reorder/loss handling

The server maintains a single `lastSeq` (demo is single-client). On every received UDP packet:
- If `seq > lastSeq`: apply `(dx, dy)`, set `lastSeq = seq`
- If `seq <= lastSeq`: drop the packet (duplicate or reordered)

Lost packets are not retransmitted. The user's finger keeps moving, so subsequent deltas naturally compensate. UDP `seq` does not wrap within a session: a u32 at 125 Hz takes ~397 days to overflow.

The server learns the client's UDP `(IP, port)` from the first packet's source address.

## ButtonId enumeration

| ID | Name | Default PC binding | Mode |
|---|---|---|---|
| `0x01` | `MOUSE_LEFT` | mouse left | hold |
| `0x02` | `MOUSE_RIGHT` | mouse right | hold |
| `0x10` | `JUMP` | Space | hold |
| `0x11` | `SNEAK` | Left Shift | hold (Android sends down/up bracketing the toggled state) |
| `0x12` | `SPRINT` | Left Ctrl | hold (Android-side toggle) |
| `0x20` | `INVENTORY` | E | tap |
| `0x21` | `DROP` | Q | tap (no UI button — only triggered by long-press on a hotbar slot) |
| `0x22` | `SWAP_HAND` | F | tap |
| `0x30` | `ESC` | Esc | tap |
| `0x40` | `HOTBAR_1` | `1` | tap |
| `0x41` | `HOTBAR_2` | `2` | tap |
| `0x42` | `HOTBAR_3` | `3` | tap |
| `0x43` | `HOTBAR_4` | `4` | tap |
| `0x44` | `HOTBAR_5` | `5` | tap |
| `0x45` | `HOTBAR_6` | `6` | tap |
| `0x46` | `HOTBAR_7` | `7` | tap |
| `0x47` | `HOTBAR_8` | `8` | tap |
| `0x48` | `HOTBAR_9` | `9` | tap |

### Toggle semantics

`SNEAK` and `SPRINT` are toggle buttons in the UI but the wire protocol is stateless. The Android client maintains the toggle state and sends `BUTTON(SNEAK, down=1)` on first tap, `BUTTON(SNEAK, down=0)` on second tap. The PC server has no toggle state — it just translates each `down` value to a key event.

### Hotbar long-press → drop sequence

The Android client implements drop via long-press on hotbar slots. The wire-level sequence the client emits when the user long-presses slot N (≥ 400 ms hold):

1. Immediately on press: send `BUTTON(HOTBAR_N, down=1)` then `BUTTON(HOTBAR_N, down=0)` to select the slot.
2. After 400 ms hold: send `BUTTON(DROP, down=1)` then `BUTTON(DROP, down=0)`.
3. While the finger remains down: repeat the DROP tap every 200 ms (continuous drop).
4. On finger lift: stop. (No additional events.)

If the user releases before 400 ms, only step 1 fires (a normal tap-to-select).

## Connection lifecycle

```
Client (Android)              Server (PC)
     │                              │
     ├─ TCP connect ────────────────▶
     │                              │
     ├─ HELLO (wantsUdp=1) ─────────▶
     │                              │
     ◀──── HELLO_ACK (udpPort=N) ───┤
     │                              │
     ├─ (if udpPort != 0) open UDP, send LOOK_DELTA →
     │                              │
     ├─ JOYSTICK / BUTTON / PING (TCP) ─▶
     │                              │
     ◀──── PONG (TCP) ──────────────┤
     │                              │
     ╳─ TCP disconnect             │
                                    │  → server calls
                                    │    mapper.ReleaseAll()
                                    │    router.ReleaseAll()
                                    │    (release all keys/buttons
                                    │    to prevent stuck-key state)
```

## Default port

`34555` (TCP and UDP listen on the same port number).
