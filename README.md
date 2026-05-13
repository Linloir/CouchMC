<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/header-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/header-light.png">
  <img alt="CouchMC" src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/header-light.png" width="100%">
</picture>

<div align="center">
  <a href="#中文">中文</a> | <a href="#english">English</a>
  <br><br>
  <img alt="Version" src="https://img.shields.io/badge/version-v0.2.0-2ea043?style=for-the-badge">
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/Linloir/mc-controller?style=for-the-badge"></a>
  <a href="https://github.com/Linloir/mc-controller/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/Linloir/mc-controller?style=for-the-badge"></a>
  <img alt=".NET 8" src="https://img.shields.io/badge/.NET-8.0-512BD4?style=for-the-badge&logo=dotnet&logoColor=white">
  <img alt="Kotlin" src="https://img.shields.io/badge/Kotlin-Android-7F52FF?style=for-the-badge&logo=kotlin&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-Apple-FA7343?style=for-the-badge&logo=swift&logoColor=white">
  <br>
  <img alt="Windows" src="https://img.shields.io/badge/Windows-10%2F11-0078D4?style=for-the-badge&logo=windows11&logoColor=white">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-000000?style=for-the-badge&logo=apple&logoColor=white">
  <img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white">
  <img alt="iOS" src="https://img.shields.io/badge/iOS-18%2B%20Preparing-000000?style=for-the-badge&logo=ios&logoColor=white">
</div>

<a id="中文"></a>

## 中文

### 项目简介

CouchMC 的初衷很简单：把手机变成一块低延迟的触屏 Minecraft Java Edition 控制器，让你可以坐在沙发上，用类似移动版 Minecraft 的手感玩 PC 版。手机负责触摸输入，电脑端服务负责把摇杆、视角滑动、按钮和快捷栏操作转换为系统级键盘与鼠标事件。

它不依赖 Minecraft Mod。核心设计是一个 **三状态模式系统**：电脑端检测 Minecraft 是否在前台、鼠标是否被游戏捕获，然后让手机自动切换为游戏内控制器、UI 光标控制器或防误触锁屏。这样背包、箱子、菜单等原生 UI 仍由 Minecraft 自己渲染，手机只负责驱动光标和输入。

### 当前支持

- **Windows 10/11 服务端**：WinUI 3 桌面应用，带托盘、开机启动、全局设置、按键绑定、窗口透明度和 Inno Setup 安装包。
- **macOS 14+ 服务端**：原生 Swift / SwiftUI 应用，支持菜单栏、Accessibility 输入注入、Liquid Glass 设置、Bonjour / UDP 发现和 bundled adb。签名与 DMG 尚未完成，所以暂不提供 DMG 安装说明。
- **Android 8.0+ 客户端**：Kotlin 原生应用，支持 Wi-Fi / USB、局域网发现、布局编辑器、触摸手势、摇杆、视角板、按钮与快捷栏。
- **iOS / iPadOS 18+ 客户端**：Swift / SwiftUI + UIKit 客户端源码已在仓库内，正在筹备 App Store 上架；目前可用 Xcode 进行开发者安装，连接方式以 Wi-Fi 为主。

### 特点

- **无需 Mod**：对 Minecraft 来说，所有操作都是普通的键盘和鼠标输入。
- **低延迟输入链路**：TCP 负责可靠控制消息，Wi-Fi 下 UDP 负责视角增量；USB 模式通过 `adb reverse` 自动走 TCP fallback。
- **移动端手感**：浮动摇杆、LookPad 视角区、快捷栏滑动、长按丢弃、音量键映射鼠标键。
- **智能模式切换**：游戏内、UI 交互、防误触三种界面自动切换，模式变化会释放按键，避免卡键。
- **可调可编辑**：电脑端可调灵敏度、曲线、死区和按键绑定；手机端可编辑控件布局并保存 profile。
- **跨平台协议**：Windows、macOS、Android、iOS 都复用同一套二进制协议与局域网发现规则。

### 截图

<table>
  <tr>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_device.png" alt="Windows device discovery"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_settings.png" alt="Windows controller settings"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_key.png" alt="Windows key bindings"></td>
  </tr>
  <tr>
    <td align="center">设备发现</td>
    <td align="center">控制参数</td>
    <td align="center">按键绑定</td>
  </tr>
</table>

<table>
  <tr>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_home.png" alt="iOS home"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_ui_edit_1.png" alt="iOS layout editor"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_ui_edit_2.png" alt="iOS layout editor controls"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_settings_1.png" alt="iOS settings"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_settings_2.png" alt="iOS advanced settings"></td>
  </tr>
  <tr>
    <td align="center">手机首页</td>
    <td align="center">布局编辑</td>
    <td align="center">控件调整</td>
    <td align="center">手机设置</td>
    <td align="center">更多设置</td>
  </tr>
</table>

### 安装

#### Windows 电脑

推荐给普通用户的方式是下载 Release 中的 `CouchMC-Setup-<version>.exe`。安装包是 per-user 安装，不需要管理员权限，程序会安装到 `%LOCALAPPDATA%\Programs\CouchMC`，并在开始菜单创建快捷方式。运行时不需要额外安装 .NET 或 Windows App SDK，ADB 也随应用一起打包。

第一次运行未签名安装包时，Windows SmartScreen 可能显示拦截提示，选择 **更多信息 → 仍要运行** 即可。Wi-Fi 模式第一次连接时，请允许 Windows Firewall 放行 CouchMC 的入站连接。

#### macOS 电脑

macOS 服务端已经可从源码构建和运行，但正式签名、notarization 和 DMG 安装包还没完成，因此暂不提供面向普通用户的 DMG 安装方式。

开发者或早期测试用户可以这样安装：

```bash
cd mac
bash scripts/fetch-adb.sh
bash scripts/install.sh
```

首次启动后，到 **System Settings → Privacy & Security → Accessibility** 为 CouchMC 授权，否则 macOS 不会接收应用发出的键盘和鼠标事件。

#### Android 手机

当前 Android 客户端可从源码构建 APK。准备 Android Studio / Android SDK、JDK 17、Gradle 8.10+，并在手机上开启开发者选项和 USB 调试。

```powershell
cd android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n cn.linloir.couchmc.android/com.mccontroller.ui.ConnectActivity
```

如果是第一次在本机编译 Android 项目，需要创建 `android/local.properties`：

```properties
sdk.dir=C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
```

#### iPhone / iPad

iOS 客户端正在筹备 App Store 上架。当前可用开发者方式安装：准备 macOS、Xcode 16+、`xcodegen` 和 iOS 18+ 真机，在 Xcode 中选择自己的 Development Team 后运行到设备。

```bash
cd ios
xcodegen generate
open McController.xcodeproj
```

iOS 版本目前以 Wi-Fi 连接为主。首次连接前请允许 Local Network 权限，否则无法发现电脑端服务。

### 使用方法

1. 在电脑上启动 CouchMC 服务端，并打开 Minecraft Java Edition。
2. 在 Windows 上建议关闭鼠标增强：Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options → 取消 **Enhance pointer precision**。Minecraft 内鼠标灵敏度建议先设为 100%，再在 CouchMC 中微调。
3. 让手机和电脑处于同一局域网，或使用 Android USB 模式。Windows / macOS 服务端会自动对已连接的 Android 设备执行 `adb reverse tcp:34555 tcp:34555`。
4. 打开手机端 CouchMC，选择自动发现的电脑，或在 Android 上点击 USB 连接。
5. 进入游戏后使用左侧摇杆移动、右侧 LookPad 控制视角、按钮执行跳跃/潜行/攻击/使用物品等操作。
6. 打开背包或菜单时，手机端会自动切换为 UI 模式，LookPad 变成光标控制区；切出 Minecraft 时进入防误触模式。
7. 根据手感在电脑端调整曲线、灵敏度、死区、按键绑定，在手机端用 Layout Editor 调整控件位置。

### 本地开发、打包与部署

#### Windows 服务端

```powershell
# Core library
dotnet build pc\McController.Core\McController.Core.csproj -c Debug

# Tests
dotnet test pc\McController.Core.Tests\McController.Core.Tests.csproj

# WinUI 3 app: use VS Build Tools MSBuild, not dotnet build
Stop-Process -Name McController.App -Force -ErrorAction SilentlyContinue
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64
Start-Process pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe
```

打包 Windows 安装器：

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 -t:Rebuild

& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\McController.iss
```

输出文件位于 `installer\out\CouchMC-Setup-<version>.exe`。如果构建时报 `apphost.exe is being used`，说明旧的 CouchMC 仍在运行，先执行 `Stop-Process -Name McController.App -Force`。

#### macOS 服务端

```bash
cd mac
bash scripts/fetch-adb.sh       # 可选但推荐，打包 adb 以支持 Android USB 自动配对
bash scripts/build.sh           # 构建到 mac/build/
bash scripts/install.sh         # 构建、复制到 /Applications、重新注册并启动
```

`scripts/build.sh release` 可以生成 Release 配置的 `.app`，但当前仍是 ad-hoc signing，不等同于可分发 DMG。新增或删除 Swift 文件后，构建脚本会自动运行 `scripts/gen-xcodeproj.swift`。

#### Android 客户端

```powershell
cd android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop cn.linloir.couchmc.android
adb shell am start -n cn.linloir.couchmc.android/com.mccontroller.ui.ConnectActivity
```

Android USB 模式通常由桌面端自动配置。手动排查时可运行：

```powershell
adb devices
adb reverse tcp:34555 tcp:34555
adb reverse --list
```

#### iOS 客户端

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

真正部署到 iPhone / iPad 时，请在 Xcode 中设置 Development Team，连接真机后 Run。App Store 上架流程正在准备，签名、权限描述、TestFlight 和商店元数据会在正式发布前补齐。

### 文档

- [架构说明](docs/architecture.md)：设计取舍、模块图、实现状态。
- [开发流程](docs/development.md)：工具链、构建命令、调试方法、常见错误。
- [协议规范](docs/protocol.md)：TCP / UDP 二进制 wire format。
- [发现协议](docs/discovery.md)：UDP broadcast、Bonjour、PROBE。
- [macOS 说明](docs/macos.md)：SwiftUI 服务端架构、Accessibility、Liquid Glass。
- [安装器说明](installer/README.md)：Windows Inno Setup 打包与卸载行为。

### 许可证

CouchMC 现在使用 [MIT License](LICENSE) 开源。

### Sponsors

如果 CouchMC 帮你把 Minecraft 搬到了沙发上，欢迎通过 [GitHub Sponsors](https://github.com/sponsors/Linloir) 支持后续开发。

### Contributors

<a href="https://github.com/Linloir/mc-controller/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Linloir/mc-controller" alt="CouchMC contributors">
</a>

### Stars 曲线

<a href="https://www.star-history.com/#Linloir/mc-controller&Date">
  <img src="https://api.star-history.com/svg?repos=Linloir/mc-controller&type=Date" alt="CouchMC star history">
</a>

<a id="english"></a>

## English

### What Is CouchMC?

CouchMC turns your phone into a low-latency touchscreen controller for Minecraft Java Edition on a computer. It was built for one very specific feeling: playing PC Minecraft from the couch with mobile-style touch controls instead of a traditional gamepad.

The phone captures joystick, look-pad, button and hotbar gestures. The desktop server translates those packets into native keyboard and mouse events. No Minecraft mod is required.

The key idea is the **three-state mode system**. The desktop app detects whether Minecraft is focused and whether its cursor is captured, then tells the phone which UI to show: in-game controller, UI cursor control, or anti-mistouch lock screen. Minecraft still renders all inventory, chest and menu screens itself; CouchMC only drives input.

### Platform Status

- **Windows 10/11 server**: WinUI 3 app with tray support, launch-at-login, global settings, key bindings, transparency preferences and an Inno Setup installer.
- **macOS 14+ server**: Native Swift / SwiftUI app with menu bar support, Accessibility input injection, Liquid Glass preferences, Bonjour / UDP discovery and bundled adb. A signed DMG is not available yet because signing and notarization are still pending.
- **Android 8.0+ client**: Native Kotlin app with Wi-Fi / USB connection, LAN discovery, layout editor, touch gestures, joystick, look pad, buttons and hotbar.
- **iOS / iPadOS 18+ client**: Swift / SwiftUI + UIKit client source is in the repository. App Store release is being prepared; developer installation through Xcode is available today.

### Highlights

- **No mod required**: Minecraft only sees regular keyboard and mouse input.
- **Low-latency transport**: TCP for reliable control messages, UDP for Wi-Fi look deltas, and TCP fallback over `adb reverse` for Android USB mode.
- **Mobile-style controls**: floating joystick, look pad, hotbar swipe, drop loop, volume-key mouse bindings and custom button gestures.
- **Automatic mode switching**: in-game, UI-interact and anti-mistouch modes are driven by the desktop server.
- **Editable feel**: tune sensitivity, curve, dead zone and bindings on desktop; edit the phone layout with saved profiles.
- **Cross-platform protocol**: Windows, macOS, Android and iOS speak the same binary protocol and LAN discovery spec.

### Screenshots

<table>
  <tr>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_device.png" alt="Windows device discovery"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_settings.png" alt="Windows controller settings"></td>
    <td width="33%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/pc_key.png" alt="Windows key bindings"></td>
  </tr>
  <tr>
    <td align="center">Device discovery</td>
    <td align="center">Controller tuning</td>
    <td align="center">Key bindings</td>
  </tr>
</table>

<table>
  <tr>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_home.png" alt="iOS home"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_ui_edit_1.png" alt="iOS layout editor"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_ui_edit_2.png" alt="iOS layout editor controls"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_settings_1.png" alt="iOS settings"></td>
    <td width="20%"><img src="https://raw.githubusercontent.com/Linloir/mc-controller/master/assets/ios_settings_2.png" alt="iOS advanced settings"></td>
  </tr>
  <tr>
    <td align="center">Phone home</td>
    <td align="center">Layout editor</td>
    <td align="center">Widget editing</td>
    <td align="center">Phone settings</td>
    <td align="center">More settings</td>
  </tr>
</table>

### Installation

#### Windows PC

For normal users, download `CouchMC-Setup-<version>.exe` from Releases. The installer is per-user, does not require admin rights, installs to `%LOCALAPPDATA%\Programs\CouchMC`, creates Start Menu shortcuts and bundles .NET, Windows App SDK and adb.

The unsigned installer may trigger Windows SmartScreen on first launch. Choose **More info → Run anyway**. For Wi-Fi mode, allow CouchMC through Windows Firewall when prompted.

#### macOS Computer

The macOS server can already be built from source, but there is no signed DMG yet. Signing, notarization and end-user packaging are still pending.

Developer install:

```bash
cd mac
bash scripts/fetch-adb.sh
bash scripts/install.sh
```

On first launch, grant Accessibility permission in **System Settings → Privacy & Security → Accessibility**. Without it, macOS drops the injected keyboard and mouse events.

#### Android Phone

Build the APK from source with Android Studio / Android SDK, JDK 17 and Gradle 8.10+. Enable Developer Options and USB debugging on the phone.

```powershell
cd android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n cn.linloir.couchmc.android/com.mccontroller.ui.ConnectActivity
```

On a fresh checkout, create `android/local.properties`:

```properties
sdk.dir=C:\\Users\\<you>\\AppData\\Local\\Android\\Sdk
```

#### iPhone / iPad

The iOS client is being prepared for the App Store. For now, install it as a developer build with macOS, Xcode 16+, `xcodegen` and a real iOS 18+ device.

```bash
cd ios
xcodegen generate
open McController.xcodeproj
```

Set your Development Team in Xcode, run on device, and allow Local Network permission. The current iOS path is Wi-Fi first.

### How To Use

1. Start the CouchMC desktop server and launch Minecraft Java Edition.
2. On Windows, disable pointer acceleration: Settings → Bluetooth & devices → Mouse → Additional mouse settings → Pointer Options → uncheck **Enhance pointer precision**. Set Minecraft mouse sensitivity to 100% as a baseline.
3. Put the phone and computer on the same LAN, or use Android USB mode. The desktop app auto-runs `adb reverse tcp:34555 tcp:34555` for connected Android devices.
4. Open CouchMC on the phone and choose a discovered desktop server, or tap USB connect on Android.
5. Use the left joystick for movement, the right LookPad for camera/cursor control, and buttons for jump, sneak, attack, use item and hotbar actions.
6. When inventory or menus open, the phone switches to UI mode. When Minecraft loses focus, the phone switches to anti-mistouch mode.
7. Tune curve, sensitivity, dead zone and bindings on desktop; adjust widget positions in the phone layout editor.

### Local Build, Packaging And Deployment

#### Windows Server

```powershell
dotnet build pc\McController.Core\McController.Core.csproj -c Debug
dotnet test pc\McController.Core.Tests\McController.Core.Tests.csproj

Stop-Process -Name McController.App -Force -ErrorAction SilentlyContinue
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Debug -p:Platform=x64 -p:RuntimeIdentifier=win-x64
Start-Process pc\McController.App\bin\x64\Debug\net8.0-windows10.0.19041.0\win-x64\McController.App.exe
```

Package the Windows installer:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
    pc\McController.App\McController.App.csproj `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 -t:Rebuild

& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\McController.iss
```

The output is `installer\out\CouchMC-Setup-<version>.exe`.

#### macOS Server

```bash
cd mac
bash scripts/fetch-adb.sh
bash scripts/build.sh
bash scripts/install.sh
```

`scripts/build.sh release` creates a Release `.app`, but it is still ad-hoc signed and not a distributable DMG.

#### Android Client

```powershell
cd android
gradle :app:assembleDebug --console=plain
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am force-stop cn.linloir.couchmc.android
adb shell am start -n cn.linloir.couchmc.android/com.mccontroller.ui.ConnectActivity
```

Manual USB diagnostics:

```powershell
adb devices
adb reverse tcp:34555 tcp:34555
adb reverse --list
```

#### iOS Client

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

For device deployment, open the generated Xcode project, configure signing and run on a connected iPhone or iPad.

### Documentation

- [Architecture](docs/architecture.md): design rationale, module map and implementation status.
- [Development](docs/development.md): toolchain, build commands, debugging and common pitfalls.
- [Protocol](docs/protocol.md): TCP / UDP binary wire format.
- [Discovery](docs/discovery.md): UDP broadcast, Bonjour and PROBE.
- [macOS](docs/macos.md): SwiftUI server architecture, Accessibility and Liquid Glass.
- [Installer](installer/README.md): Windows Inno Setup packaging and uninstall behavior.

### License

CouchMC is open-sourced under the [MIT License](LICENSE).

### Sponsors

If CouchMC helps you play Minecraft from the couch, you can support development through [GitHub Sponsors](https://github.com/sponsors/Linloir).

### Contributors

<a href="https://github.com/Linloir/mc-controller/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Linloir/mc-controller" alt="CouchMC contributors">
</a>

### Star History

<a href="https://www.star-history.com/#Linloir/mc-controller&Date">
  <img src="https://api.star-history.com/svg?repos=Linloir/mc-controller&type=Date" alt="CouchMC star history">
</a>
