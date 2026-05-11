# MC Controller — LAN Discovery Protocol

This document specifies how the Android client discovers PC servers on
the local network without the user having to type an IP address. It is
the single source of truth for both the PC server's discovery advertiser
and the Android client's discovery listener.

Two parallel mechanisms are defined for maximum compatibility:

1. **UDP broadcast** (primary, simple, always-works-on-LAN)
2. **mDNS / DNS-SD** (secondary, plays nicely with routers / multicast
   filters that drop unsolicited broadcasts but allow mDNS through)

A client SHOULD listen on both simultaneously and merge results by
`(ip, tcpPort)`. A server SHOULD advertise on both, but advertising on
just UDP broadcast is sufficient for the home-LAN use case.

---

## Design rationale

- **PC announces, phone listens.** The PC is the configurable side (port
  is user-editable) and the phone has no prior knowledge of the port. If
  the phone probed, it would not know what port to probe on. PC
  broadcasting solves this naturally.
- **Cleartext, no auth.** Same-LAN demo; threat model is trivial.
- **Short, fixed-prefix payload.** Lets a listener cheaply reject foreign
  packets (random UDP noise on the broadcast channel) without parsing.
- **Heartbeat-style.** PC re-broadcasts every second so a phone that
  joins the network mid-session discovers the server within ~1s. No
  explicit "WHOIS?" request from the phone.

---

## Channel A — UDP broadcast (primary)

### Wire format

```
+-------+-------+-------+-------+--------+--------+--------+----------+
| 'M'   | 'C'   | 'C'   | 'T'   |  ver   | msg    | flags  | tcpPort  |
| 0x4D  | 0x43  | 0x43  | 0x54  |  u8    | u8     | u8     | u16 BE   |
+-------+-------+-------+-------+--------+--------+--------+----------+
| nameLen u16 BE | name (UTF-8, exactly nameLen bytes, max 255)       |
+-----------------+----------------------------------------------------+
```

Total: **11 + nameLen** bytes. Min 11 (empty name), max 266.

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0  | 4 | magic | ASCII `"MCCT"` (`0x4D 0x43 0x43 0x54`). Reject if not exact. |
| 4  | 1 | ver | Protocol version, currently `0x01`. Reject if unsupported. |
| 5  | 1 | msgType | `0x01` = `ANNOUNCE` (PC→clients). Reserved range `0x02..0xFF`. |
| 6  | 1 | flags | Bit field, see below. |
| 7  | 2 | tcpPort | TCP listener port of the control channel, big-endian. |
| 9  | 2 | nameLen | UTF-8 byte length of the name. Big-endian. Max value 255. |
| 11 | N | name | Human-readable host name. Plain UTF-8. No null terminator. |

### Flag bits

| Bit | Name | Meaning |
|---|---|---|
| 0 | `MC_IN_FOREGROUND` | `1` = the server detects Minecraft is the foreground window right now; `0` = MC not detected. Lets the phone UI show a green/amber dot per host. |
| 1 | `ACCEPTS_UDP` | `1` = the server has a UDP listener bound and accepts WiFi-mode UDP `LOOK_DELTA` packets; `0` = TCP-only (e.g. server is in degraded mode). |
| 2 | `BUSY` | `1` = a client is already connected (demo is single-client). Phone may still display the host but should warn before attempting connection. |
| 3..7 | reserved | Sender MUST set to `0`; receiver MUST tolerate non-zero (future flags). |

### Network details

- **Destination address**: `255.255.255.255` (limited broadcast). MUST
  bind to all wired+wireless interfaces and broadcast on each (PCs with
  both Ethernet and WiFi MUST send on both). Optional: also send on
  per-interface directed broadcast (`192.168.x.255`) for routers that
  drop limited broadcast.
- **Destination port**: `34556` (one above the default control port).
- **Source port**: ephemeral (don't bind to a fixed source port).
- **Cadence**: every `1000 ± 100 ms` (jitter to avoid sync between
  multiple servers on the same LAN).
- **Burst on startup**: 3 packets within the first second after the
  server starts (at 0ms, 100ms, 300ms) to minimize discovery latency
  when both the phone and PC start near-simultaneously.
- **Burst on port change**: when the user changes the listen port via
  the tuning UI, send the same 3-packet burst immediately after the
  rebind.

### Receiver rules (Android)

- Bind to UDP `0.0.0.0:34556`, enable `SO_REUSEADDR`, enable broadcast.
- For each received datagram:
  - Reject if `< 11` bytes.
  - Reject if magic ≠ `"MCCT"`.
  - Reject if `ver != 0x01`.
  - Reject if `msgType != 0x01`.
  - Reject if `nameLen > (len - 11)` (truncated).
  - Extract sender's source IP from the datagram envelope (NOT from
    the payload — keeps the payload smaller and the source IP can't
    be spoofed within LAN trivially).
  - Emit `(ip, tcpPort, name, flags, lastSeenMillis = now)`.
- A host disappears from the discovery list if no advertisement has
  arrived for `> 5000 ms`. The phone UI MAY keep showing it but visibly
  fade it out / mark it as stale.

### Example packet

A server named "JonDesk" with TCP port `34555`, MC foregrounded, accepts
UDP, not busy:

```
4D 43 43 54  01  01  03  87 0B  00 07  4A 6F 6E 44 65 73 6B
^^^^^^^^^^^ MCCT
            ^^ ver=1
               ^^ msg=ANNOUNCE
                  ^^ flags = 0b0000_0011 (mc_foreground + accepts_udp)
                     ^^^^^ tcpPort = 0x870B = 34555
                           ^^^^^ nameLen = 7
                                 ^^^^^^^^^^^^^^^^^^^^ "JonDesk"
```

Total length: 18 bytes.

---

## Channel B — mDNS / DNS-SD (secondary)

Implementations SHOULD also advertise via standard zeroconf/mDNS so the
Android `NsdManager` API and any standard `dns-sd` browser can see the
server.

### Service registration

- **Service type**: `_mccontroller._tcp.local.`
- **Service instance name**: same human-readable name as the UDP
  `name` field. Example: `JonDesk._mccontroller._tcp.local.`
- **Host name**: the OS hostname (`<host>.local.`)
- **Port**: the TCP control-channel port (same as the UDP `tcpPort`).
- **TTL**: default mDNS TTL (120 s) is fine.

### TXT records

| Key | Value | Required | Notes |
|---|---|---|---|
| `v`  | `1`           | yes | Protocol version (matches UDP `ver` field). |
| `mc` | `1` or `0`    | yes | MC foreground state (matches UDP flag bit 0). |
| `udp`| `1` or `0`    | yes | Accepts UDP (matches UDP flag bit 1). |
| `busy`| `1` or `0`   | optional | Defaults to `0` if absent. |

When the foreground or UDP-accept state changes, the server SHOULD
re-announce (TXT-record update). DNS-SD subscribers will receive the
update without needing to poll.

### Android implementation note

`android.net.nsd.NsdManager.discoverServices("_mccontroller._tcp", PROTOCOL_DNS_SD, listener)`.
The client merges mDNS-discovered hosts with UDP-discovered ones keyed
by `(ip, tcpPort)`. If both channels report the same host, the union of
their data is used (mDNS provides TXT records, UDP provides the
last-seen timestamp).

### PC implementation note

On .NET, recommended libraries (in order of preference):
1. **`Makaretu.Dns.Multicast`** (pure managed mDNS responder, MIT)
2. **`Tmds.MDns`** (pure managed, MIT)
3. Roll-your-own UDP multicast on `224.0.0.251:5353` (works but more
   plumbing than worthwhile for a demo).

mDNS is **optional**. A server that only implements Channel A is
fully spec-compliant. A client that only implements Channel A is
also fully spec-compliant.

---

## Compatibility matrix

| Server channels | Client channels | Result |
|---|---|---|
| UDP only | UDP only | ✅ Works |
| UDP only | UDP + mDNS | ✅ UDP path only |
| UDP + mDNS | UDP only | ✅ UDP path only |
| UDP + mDNS | UDP + mDNS | ✅ Both paths, deduped |
| mDNS only | UDP only | ❌ Not discoverable |
| mDNS only | UDP + mDNS | ✅ mDNS path only |

**Recommendation**: server implements at least Channel A. Channel B is
a quality-of-life addition for friendlier router environments.

---

## Versioning

If a future revision needs to change the UDP wire format incompatibly,
bump `ver` to `0x02`. Servers MAY send both versions in alternating
packets during a transition window. Clients that don't know the new
version simply ignore those packets (rejected at the `ver` check).

For the mDNS channel, bump the `v` TXT-record value alongside.

---

## Default ports

| Port | Used for |
|---|---|
| `34555` | TCP control + WiFi UDP (when the server's TCP port is at its default). The port advertised in the discovery `tcpPort` field is whatever the server is actually listening on, which may differ. |
| `34556` | UDP discovery broadcast destination. **Always** this port regardless of the server's TCP port — the well-known discovery port lets the client receive announces from servers running on any TCP port. |
| `5353` (UDP) | Standard mDNS multicast group `224.0.0.251`. Used by Channel B only. |
