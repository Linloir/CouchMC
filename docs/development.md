# Development workflow

> Build / install / debug commands and the gotchas you'll hit. Companion to [architecture.md](architecture.md).

## 1. Toolchain

| Tool | Version | Why | Install |
|---|---|---|---|
| .NET 8 SDK | 8.0.x | PC server build target | `winget install Microsoft.DotNet.SDK.8` |
| Android Studio | Hedgehog (2023.1.1) or newer | Optional — only for IDE work | Download from developer.android.com |
| Android SDK + platform-tools | API 34 | `adb` + SDK headers | Comes with Android Studio; or standalone command-line tools |
| Gradle | 8.10+ | Android build (we use system gradle directly, not the wrapper) | `winget install Gradle.Gradle` or via Scoop |
| JDK 17 | 17.0.x | Android compile | `winget install Microsoft.OpenJDK.17` or Android Studio's bundled JDK |
| Git | any recent | source control | `winget install Git.Git` |

**Phone**: API 26+ (Android 8.0+), USB debugging enabled, OEM driver installed.

**Verification**:
```powershell
dotnet --list-sdks    # expect 8.0.x
adb version           # expect 1.0.41+
gradle --version      # expect 8.10.x with JDK 17
java -version
```

The repo's `android/local.properties` (gitignored) needs `sdk.dir` pointing at your Android SDK install:
```properties
sdk.dir=C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
```

## 2. Repo layout

```
mc_controller/
├── CLAUDE.md                       AI agent orientation (read this first)
├── README.md                       User-facing overview
├── .gitignore                      .NET + Android Studio standard
├── docs/
│   ├── architecture.md             Design + module map (THIS REPO'S BRAIN)
│   ├── development.md              You are here
│   └── protocol.md                 Wire protocol spec (PC/Android codecs mirror it)
├── pc/
│   ├── McController.sln
│   ├── McController.Server/        the server
│   └── McController.Server.Tests/  xUnit, 40 tests
├── android/
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── gradle/libs.versions.toml   version catalog
│   ├── local.properties            (gitignored, machine-specific)
│   └── app/...
└── tools/                          helper scripts (TBD)
```

## 3. Build / run

### PC server

```powershell
# Build
dotnet build E:\dev\personal\mc_controller\pc\McController.sln -c Debug

# Run (foreground; opens both console + tuning Form)
dotnet run --project E:\dev\personal\mc_controller\pc\McController.Server

# SendInput self-test (smoke-checks the OS injection path against MC)
dotnet run --project E:\dev\personal\mc_controller\pc\McController.Server --selftest

# Tests
dotnet test E:\dev\personal\mc_controller\pc\McController.sln  # expect 40/40 pass
```

**Common pitfall** — the build fails with:
```
error MSB3027: Could not copy "...\apphost.exe" to "...\McController.Server.exe".
The process cannot access the file because it is being used by another process.
```
Means the previous server is still running. Kill it:
```powershell
Stop-Process -Name McController.Server -Force -ErrorAction SilentlyContinue
```
Then rebuild.

### Android app

```powershell
# Build (use the system gradle; no wrapper jar in repo)
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug --console=plain

# Output APK
# → android/app/build/outputs/apk/debug/app-debug.apk

# Install + relaunch (phone must be authorized for adb)
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop com.mccontroller
adb shell am start -n com.mccontroller/.ui.ConnectActivity
```

First-run on a new machine: `local.properties` doesn't exist yet. Create it manually per "Toolchain" above; otherwise the build fails with "SDK location not found."

If you've never run on this phone before:
1. Enable Developer Options (tap Build Number 7×)
2. Enable USB Debugging
3. `adb devices` — should list as "device" not "unauthorized"
4. If "unauthorized", accept the prompt on the phone (tick "Always allow")

### USB mode setup

```powershell
adb reverse tcp:34555 tcp:34555
adb reverse --list                  # expect "UsbFfs tcp:34555 tcp:34555"
```
This forwards `127.0.0.1:34555` on the phone to `127.0.0.1:34555` on the PC over USB. The Android app's "Connect (USB / 127.0.0.1)" button uses this. Re-run after every USB disconnect.

(Step 12 will automate this on PC server launch; not yet wired.)

## 4. Day-to-day loop

A typical incremental iteration:

```powershell
# 1. Edit code in your IDE / VS Code

# 2. PC side change?
Stop-Process -Name McController.Server -Force -ErrorAction SilentlyContinue
dotnet build E:\dev\personal\mc_controller\pc\McController.sln
dotnet run --project E:\dev\personal\mc_controller\pc\McController.Server

# 3. Android side change?
cd E:\dev\personal\mc_controller\android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop com.mccontroller
adb shell am start -n com.mccontroller/.ui.ConnectActivity

# 4. Test:
#    - Phone displays Connect screen
#    - Pick profile, tap "Connect (USB)"
#    - HUD shows "● USB · in-game · Xms"
#    - Tweak feel via Tuning Form sliders (live; no reconnect needed)
```

Gradle's configuration cache makes incremental Android builds ~3 s. PC builds ~3 s with hot daemons.

## 5. Critical pre-game settings (Windows)

Before testing camera control for the first time on a new machine:

1. Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options
2. **Uncheck "Enhance pointer precision"**. With it on, injected mouse deltas get filtered through OS acceleration and the in-game camera feels gummy / inconsistent.
3. Inside MC: Set Mouse Sensitivity to **100%** as a baseline. Then tune `Look (User) → Sensitivity` in the TuningForm. Default is 1.5.

## 6. Connection setup recap

| Mode | What you need | Latency baseline |
|---|---|---|
| WiFi | PC + phone on same network (5 GHz strongly preferred). Enter PC's IPv4 (shown in server banner) in the Android Connect screen. | ~10–25 ms P50 |
| USB | `adb reverse tcp:34555 tcp:34555` once per cable session. Use the "Connect (USB)" button. | ~3–8 ms P50 |

If neither connects: check the server banner output for the actual port + bound addresses, and that Windows Firewall isn't blocking inbound on the chosen port (only WiFi mode is affected).

## 7. Debugging

### Mode detection is wrong on PC
- TuningForm's status panel shows the current MC mode (`In-game / UI interact / Anti-mistouch`) in green/blue/orange.
- Verify `WindowStateMonitor` is detecting the right process: check `_matchProcessNames` (defaults: `javaw`, `java`, `minecraft`). Add your launcher's process name there if needed.

### Wire packet diagnostics
- PC console logs every `HELLO`, client connect/disconnect, mode change, and per-second `pkts/s J/L/B` summary.
- Per-second counts ≈ packets the server *accepted* (UDP-dropped doesn't count); compare against expected — joystick ~30–60 Hz when moving, LOOK ~80–125 Hz when swiping, BUTTON edge-triggered.

### Stuck-key bug (post-disconnect)
- Should be impossible: `OnClientDisconnected` calls `mapper.ReleaseAll()` + `router.ReleaseAll()`. If it ever recurs, check those are reachable in your code path.

### Touch events not reaching joystick / lookpad
- Look at the FrameLayout child order in `activity_controller.xml`. **All editable widgets must be direct children of root** — wrapping kills multi-touch split.
- The `EditorCanvas` deliberately intercepts multi-touch via `onInterceptTouchEvent`; that's editor-only and shouldn't affect the runtime ControllerActivity.

### Build errors

| Error | Cause | Fix |
|---|---|---|
| `error MSB3027: ...apphost.exe is being used` (PC) | Server still running | `Stop-Process -Name McController.Server -Force` |
| `error SYSLIB1062: LibraryImportAttribute requires unsafe code` (PC) | `<AllowUnsafeBlocks>` missing from csproj | Add it under `<PropertyGroup>` (already in current csproj) |
| `error CS0119: 'MouseButton' is a method... invalid` (PC) | Method named same as enum | Methods using `MouseButton` parameter renamed to `SetMouseButton` |
| `Unresolved reference: repeatOnLifecycle` (Android) | Missing `androidx.lifecycle:lifecycle-runtime-ktx` | Already in `libs.versions.toml`; if dropped, re-add |
| `SDK location not found` (Android) | Missing `android/local.properties` | Create one with `sdk.dir=<your Android SDK path>` |
| `e: ... ref and unsafe in async... preview only` (Kotlin? No — but C#) | C# 12 doesn't allow ref-struct in async methods | Extract span-using code into a synchronous helper (see `TcpServer.ProcessAndCompactBuffer`) |

## 8. Tests

```powershell
dotnet test E:\dev\personal\mc_controller\pc\McController.sln
```

Covers:
- `PacketCodecTests` — round-trip TCP/UDP encode/decode, partial frames, unknown type bytes
- `JoystickToWasdMapperTests` — hysteresis, direction reversal, dead-zone behavior, **regression for "stuck A key" with all-zero thresholds**
- `CameraCurveTests` — Linear pass-through, residual carry, Power-curve cap
- `ButtonRouterTests` — key/mouse routing, `ReleaseAll` correctness

40 tests as of this commit. Keep green.

No Android instrumented tests yet — testing has been manual through the editor + in-MC verification.

## 9. Releasing / packaging

Not in scope for the current demo phase. When ready:
- PC: `dotnet publish -c Release -r win-x64 --self-contained -p:PublishAot=true` for a single-file native binary. Add Wix or Inno Setup wrapper.
- Android: `gradle :app:bundleRelease` for an AAB with signing; or `assembleRelease` for an APK.

## 10. Where to look when picking up dev

1. **[architecture.md](architecture.md)** — start here; the module map and design-decisions sections orient you to the codebase
2. **[protocol.md](protocol.md)** — when touching either the PC's `PacketCodec.cs` or the Android's `PacketCodec.kt`, keep them in sync
3. **`pc/McController.Server/Program.cs`** — top-level entrypoint; all wiring lives here
4. **`android/.../ui/ControllerActivity.kt`** — the same role on Android (lifecycle + wiring)
5. **Latest git log** — `git log --oneline -20` shows the recent evolution and commit-message rationales are reasonably thorough
