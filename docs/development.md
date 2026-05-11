# Development workflow

> Build / install / debug commands and the gotchas you'll hit. Companion to [architecture.md](architecture.md).

## 1. Toolchain

| Tool | Version | Why | Install |
|---|---|---|---|
| .NET 8 SDK | 8.0.x | Builds `McController.Core` + tests | `winget install Microsoft.DotNet.SDK.8` |
| VS 2022 Build Tools | 17.x | MSBuild + Windows App SDK targets needed by `McController.App` | `winget install Microsoft.VisualStudio.2022.BuildTools` then in the installer add **".NET desktop build tools"** + **"Windows App SDK C# Templates"** |
| Windows App SDK runtime | 1.7+ | Bundled in `McController.App` via `WindowsAppSDKSelfContained=true`; end users don't need a separate install |  |
| Inno Setup 6 | 6.x | Builds the Windows installer | `winget install JRSoftware.InnoSetup` |
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
│   ├── protocol.md                 Wire protocol spec (PC/Android codecs mirror it)
│   ├── discovery.md                LAN announce / mDNS / PROBE spec
│   └── porting.md                  iOS + macOS migration plan
├── pc/
│   ├── McController.sln
│   ├── McController.Core/          protocol + input + diag + config (.NET 8)
│   ├── McController.Core.Tests/    xUnit, 53 tests
│   └── McController.App/           WinUI 3 desktop shell (Windows-only)
├── installer/
│   ├── McController.iss            Inno Setup script
│   └── README.md                   How to build the installer
├── android/
│   ├── settings.gradle.kts
│   ├── build.gradle.kts
│   ├── gradle.properties
│   ├── gradle/libs.versions.toml   version catalog
│   ├── local.properties            (gitignored, machine-specific)
│   └── app/...
```

## 3. Build / run

### PC core + tests (plain dotnet)

```powershell
# Core library
dotnet build pc\McController.Core\McController.Core.csproj -c Debug

# Tests
dotnet test  pc\McController.Core.Tests\McController.Core.Tests.csproj  # expect 53/53 pass
```

### PC App (WinUI 3 — use MSBuild, not `dotnet build`)

The `McController.App` project depends on Windows App SDK MSBuild targets that **only resolve under VS BuildTools' MSBuild**, not the plain `dotnet build` host. `dotnet build` of the App project fails with cryptic `Pri.Tasks.dll` / resource-packaging errors. Use the MSBuild path explicitly:

```powershell
# Stop any running instance (the EXE holds itself open)
Stop-Process -Name McController.App -Force -ErrorAction SilentlyContinue

# Build (Debug, x64)
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64

# Run
Start-Process pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe

# SendInput self-test (smoke-checks the OS injection path against MC)
& "<above exe path>" --selftest
```

**Common pitfall** — the build fails with:
```
error MSB3027: Could not copy "...\apphost.exe" to "...\McController.App.exe".
The process cannot access the file because it is being used by another process.
```
Means the previous app is still running. Kill it:
```powershell
Stop-Process -Name McController.App -Force -ErrorAction SilentlyContinue
```
Then rebuild.

### Cutting an installer (Release publish + Inno Setup)

See [installer/README.md](../installer/README.md). The summary:

```powershell
# 1. Release publish
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 -t:Rebuild

# 2. Compile installer
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\McController.iss

# → installer\out\McController-Setup-<version>.exe
```

### Android app

```powershell
# Build (use the system gradle; no wrapper jar in repo)
cd android
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

In practice you don't need to run this by hand any more — the PC app's
`AdbDiscovery` service polls `adb devices` every 3 s and fires `adb reverse`
per detected device automatically. The manual command is still useful for
diagnostics.

## 4. Day-to-day loop

A typical incremental iteration:

```powershell
# 1. Edit code in your IDE / VS Code

# 2. Core-only change (codec, mapper, curve, etc.)?
dotnet build pc\McController.Core\McController.Core.csproj
# … the App project will rebuild against the fresh Core DLL on its next launch.

# 3. PC App / UI change?
Stop-Process -Name McController.App -Force -ErrorAction SilentlyContinue
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64
Start-Process pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe

# 4. Android side change?
cd android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop com.mccontroller
adb shell am start -n com.mccontroller/.ui.ConnectActivity

# 5. Test:
#    - Phone displays Connect screen with discovered LAN servers + USB option
#    - Pick a server or tap "Connect (USB)" (PC has already adb-reversed)
#    - HUD shows "● USB · in-game · Xms"
#    - Tweak feel via in-app Settings → 视角 sliders (live; no reconnect needed)
```

Gradle's configuration cache makes incremental Android builds ~3 s. PC App MSBuild incremental builds ~3-5 s; full Rebuild is ~20 s.

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
- The status pill on the Discovery page shows the current connection + mode.
- Verify `WindowStateMonitor` is detecting the right process: check `_matchProcessNames` (defaults: `javaw`, `java`, `minecraft`). Add your launcher's process name there if needed.

### Wire packet diagnostics
- The app's `errors.log` at `%LOCALAPPDATA%\McController\errors.log` captures any unhandled exceptions.
- For per-packet counts, look at the Settings page's status panel or the Android HUD (latter shows P50 RTT live).

### Stuck-key bug (post-disconnect)
- Should be impossible: `OnClientDisconnected` calls `mapper.ReleaseAll()` + `router.ReleaseAll()`. If it ever recurs, check those are reachable in your code path.

### Touch events not reaching joystick / lookpad
- Look at the FrameLayout child order in `activity_controller.xml`. **All editable widgets must be direct children of root** — wrapping kills multi-touch split.
- The `EditorCanvas` deliberately intercepts multi-touch via `onInterceptTouchEvent`; that's editor-only and shouldn't affect the runtime ControllerActivity.

### Build errors

| Error | Cause | Fix |
|---|---|---|
| `error MSB3027: ...apphost.exe is being used` (PC) | App still running | `Stop-Process -Name McController.App -Force` |
| `error MSB4226: The imported project "...Microsoft.Build.Sdk.Pri.targets" was not found` | Building `McController.App` with `dotnet build` instead of MSBuild | Use the VS BuildTools' MSBuild path; install the **Windows App SDK C# Templates** workload via the VS Installer |
| `error SYSLIB1062: LibraryImportAttribute requires unsafe code` (PC) | `<AllowUnsafeBlocks>` missing from csproj | Add it under `<PropertyGroup>` (already in current csproj) |
| `error CS0119: 'MouseButton' is a method... invalid` (PC) | Method named same as enum | Methods using `MouseButton` parameter renamed to `SetMouseButton` |
| `Unresolved reference: repeatOnLifecycle` (Android) | Missing `androidx.lifecycle:lifecycle-runtime-ktx` | Already in `libs.versions.toml`; if dropped, re-add |
| `SDK location not found` (Android) | Missing `android/local.properties` | Create one with `sdk.dir=<your Android SDK path>` |
| `e: ... ref and unsafe in async... preview only` (C#) | C# 12 doesn't allow ref-struct in async methods | Extract span-using code into a synchronous helper (see `TcpServer.ProcessAndCompactBuffer`) |

## 8. Tests

```powershell
dotnet test pc\McController.Core.Tests\McController.Core.Tests.csproj
```

Covers:
- `PacketCodecTests` — round-trip TCP/UDP encode/decode, partial frames, unknown type bytes (16)
- `JoystickToWasdMapperTests` — hysteresis, direction reversal, dead-zone behavior, **regression for "stuck A key" with all-zero thresholds** (13)
- `CameraCurveTests` — Linear pass-through, residual carry, Power-curve cap (7)
- `ButtonRouterTests` — key/mouse routing, `ReleaseAll` correctness (8)
- `LanDiscoveryAdvertiserTests` — broadcast cadence, flag bit packing (5)
- `TcpServerProbeTests` — PROBE/PROBE_ACK reachability path, no client-events fire (4)

53 tests as of this commit. Keep green.

No Android instrumented tests yet — testing has been manual through the editor + in-MC verification.

## 9. Releasing / packaging

The Windows path is wired:

1. Release publish of `McController.App` (full self-contained, includes WindowsAppSDK runtime).
2. Inno Setup script in `installer/McController.iss` produces a per-user installer that drops the app in `%LOCALAPPDATA%\Programs\McController\` and registers an Add/Remove Programs entry.
3. Output: `installer\out\McController-Setup-<version>.exe` (~80–90 MB).

See [installer/README.md](../installer/README.md) for the build + distribution checklist.

For Android, no release pipeline is wired yet — `gradle :app:bundleRelease` would produce an AAB once signing is configured.

## 10. Cross-platform / porting

For the macOS server + iOS client roadmap, see [porting.md](porting.md). The wire spec ([protocol.md](protocol.md)) and discovery spec ([discovery.md](discovery.md)) are deliberately platform-neutral, so once the Windows-only files inside `McController.Core` are split out into a separate platform project, the rest of the .NET code drops onto macOS unchanged.

## 11. Where to look when picking up dev

1. **[architecture.md](architecture.md)** — start here; the module map and design-decisions sections orient you to the codebase
2. **[protocol.md](protocol.md)** — when touching the PC's `PacketCodec.cs` or the Android's `PacketCodec.kt`, keep them in sync
3. **`pc/McController.App/Services/ServerHost.cs`** — top-level wiring on the PC side (replaces the old `Program.cs` that lived in the WinForms-era `McController.Server` project)
4. **`pc/McController.App/MainWindow.xaml(.cs)`** — UI shell entry, NavigationView + page routing + transparency brushes
5. **`android/.../ui/ControllerActivity.kt`** — the same role on Android (lifecycle + wiring)
6. **Latest git log** — `git log --oneline -20` shows the recent evolution and commit-message rationales are reasonably thorough
