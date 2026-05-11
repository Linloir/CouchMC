using System;
using System.Collections.Generic;
using System.Globalization;

namespace McController.App.Util;

/// <summary>
/// Minimal i18n lookup. Two embedded dictionaries (Simplified Chinese
/// + English); the active one is picked once at startup from the user's
/// current UI culture. Strings are addressed by stable dot-separated
/// keys (e.g. <c>"settings.title"</c>). Unknown keys fall back to the
/// supplied default so missing translations show the developer-supplied
/// string instead of "??(key)??".
///
/// We use a hand-rolled table instead of .resw + x:Uid because the
/// resw / MRT pipeline for unpackaged WinUI 3 needs the AppxPackage
/// tooling at runtime — extra setup that doesn't buy us much for two
/// languages. The trade-off: code-behind has to call
/// <see cref="Get"/> on each TextBlock instead of declarative x:Uid.
/// </summary>
public static class L
{
    // Lazy so static-field-init ordering doesn't fail us: the language
    // dictionaries (ZhHans / EnUs) are declared further down in the file
    // and aren't populated until their own static initializers run; a
    // direct `Pick()` call at field-init time saw them as null.
    private static readonly Lazy<Dictionary<string, string>> _dict = new(Pick);

    /// <summary>
    /// Returns the localized string for <paramref name="key"/>, or
    /// <paramref name="fallback"/> if the key is missing. <c>fallback</c>
    /// also serves as the developer's reference English / Chinese text
    /// for keys still waiting on a translation.
    /// </summary>
    public static string Get(string key, string fallback = "")
    {
        return _dict.Value.TryGetValue(key, out var v) && !string.IsNullOrEmpty(v)
            ? v
            : fallback;
    }

    /// <summary>Two-letter language tag of the active dictionary (e.g. "zh" / "en").</summary>
    public static string ActiveLanguageTag { get; } =
        (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName ?? "en").ToLowerInvariant();

    private static Dictionary<string, string> Pick()
    {
        var lang = (CultureInfo.CurrentUICulture.TwoLetterISOLanguageName ?? "en").ToLowerInvariant();
        return lang switch
        {
            "zh" => ZhHans,
            _    => EnUs,
        };
    }

    // ===== Translation tables =====
    // Keys are dot-separated namespaces so they stay self-documenting:
    //   "nav.discovery"        — sidebar label
    //   "discovery.lan.header" — LAN section card header
    //   "settings.profile.delete" — button text

    private static readonly Dictionary<string, string> ZhHans = new()
    {
        // App-wide
        ["app.title"] = "MC Controller",
        ["app.tooltip"] = "MC Controller",

        // Tray menu
        ["tray.open"] = "打开面板",
        ["tray.exit"] = "退出服务",

        // Navigation
        ["nav.root"] = "移动控制器",
        ["nav.discovery"] = "设备发现",
        ["nav.settings"] = "设置",
        ["nav.global"] = "全局设置",
        ["nav.about"] = "关于",

        // Discovery page
        ["discovery.title"] = "设备发现",
        ["discovery.subtitle"] = "发现可用的 USB 与局域网设备并选作控制器",
        ["discovery.status.section"] = "状态",
        ["discovery.status.header"] = "当前连接",
        ["discovery.status.waiting"] = "等待连接...",
        ["discovery.status.connected"] = "已连接: {0}",
        ["discovery.pill.connected"] = "已连接",
        ["discovery.pill.disconnected"] = "未连接",
        ["discovery.usb.section"] = "USB 设备",
        ["discovery.usb.empty.header"] = "请连接 USB 设备",
        ["discovery.usb.empty.desc"] = "用数据线连接手机并开启 USB 调试，连接后会自动通过 adb reverse 转发端口 34555，手机端连接 127.0.0.1 即可。",
        ["discovery.usb.appInstalled"] = "已安装 App",
        ["discovery.lan.section"] = "局域网设备",
        ["discovery.lan.header"] = "正在向局域网广播服务地址",
        ["discovery.lan.desc"] = "每秒向 UDP 34556 广播 ANNOUNCE 包，手机端连接界面会自动列出本机。",
        ["discovery.net.section"] = "本机网络",
        ["discovery.net.header"] = "本机 IP 地址",
        ["discovery.net.desc"] = "在手机端输入其中一个作为服务端地址（WiFi 模式）",

        // Settings page
        ["settings.title"] = "设置",
        ["settings.subtitle"] = "服务、配置方案与视角曲线",
        ["settings.service.section"] = "服务",
        ["settings.service.port.header"] = "服务端口",
        ["settings.service.port.listening"] = "服务正在监听...",
        ["settings.profile.section"] = "配置方案",
        ["settings.profile.current.header"] = "当前方案",
        ["settings.profile.current.desc"] = "切换不同的灵敏度、曲线与死区组合",
        ["settings.profile.name.header"] = "方案名称",
        ["settings.profile.name.desc"] = "仅作显示用",
        ["settings.profile.manage.header"] = "方案管理",
        ["settings.profile.manage.desc"] = "新建、复制、删除或恢复当前方案",
        ["settings.profile.new"] = "新建",
        ["settings.profile.duplicate"] = "复制",
        ["settings.profile.restore"] = "恢复默认",
        ["settings.profile.delete"] = "删除",
        ["settings.profile.delete.confirm"] = "确定要删除「{0}」？",
        ["settings.profile.delete.title"] = "删除配置方案",
        ["settings.profile.restore.confirm"] = "将当前方案「{0}」的灵敏度、曲线与死区参数重置为默认值？",
        ["settings.profile.restore.title"] = "恢复默认设置",
        ["settings.profile.atLeastOne"] = "至少保留一个方案",
        ["settings.profile.newName"] = "新方案 {0}",
        ["settings.camera.section"] = "视角",
        ["settings.camera.sensitivity.header"] = "灵敏度",
        ["settings.camera.sensitivity.desc"] = "鼠标移动的整体放大倍率（建议先关闭 Windows 的「提高指针精度」）",
        ["settings.camera.curve.header"] = "曲线（高级）",
        ["settings.camera.curve.desc"] = "Linear 仅受灵敏度控制；Power 在此基础上叠加加速曲线",
        ["settings.camera.curve.type"] = "曲线类型",
        ["settings.camera.curve.linear"] = "Linear（线性）",
        ["settings.camera.curve.power"] = "Power（带加速）",
        ["settings.camera.curve.factor"] = "加速强度",
        ["settings.camera.curve.exp"] = "加速指数",
        ["settings.camera.curve.maxmul"] = "最大放大倍率",
        ["settings.camera.curve.preview"] = "实时预览",
        ["settings.camera.curve.legend.curve"] = "当前曲线（灵敏度 × 加速）",
        ["settings.camera.curve.legend.ref"] = "y = x 参考线（无放大基准）",
        ["settings.movement.section"] = "移动",
        ["settings.movement.deadzone.header"] = "死区",
        ["settings.movement.deadzone.desc"] = "摇杆中心忽略的范围",
        ["settings.movement.enter.header"] = "进入阈值",
        ["settings.movement.enter.desc"] = "开始按下方向键的阈值",
        ["settings.movement.exit.header"] = "退出阈值",
        ["settings.movement.exit.desc"] = "松开方向键的阈值（须小于进入阈值，提供滞回）",
        ["settings.save.saved"] = "已保存",
        ["settings.save.failed"] = "保存失败: {0}",
        ["settings.dialog.ok"] = "确定",
        ["settings.dialog.cancel"] = "取消",

        // Global settings
        ["global.title"] = "全局设置",
        ["global.subtitle"] = "影响整个应用的行为，跨配置方案生效",
        ["global.section.general"] = "通用",
        ["global.startup.header"] = "开机时启动",
        ["global.startup.desc"] = "登录 Windows 后在后台自动运行，托盘图标常驻待机",
        ["global.section.appearance"] = "外观",
        ["global.transparency.header"] = "启用透明效果",
        ["global.transparency.desc"] = "窗口背景使用 Acrylic 模糊；关闭后改为不透明纯色",
        ["global.chrome.header"] = "侧栏与标题栏不透明度",
        ["global.chrome.desc"] = "0% = 完全透明（纯 Acrylic）；100% = 完全遮盖壁纸",
        ["global.content.header"] = "内容区域不透明度",
        ["global.content.desc"] = "壁纸太鲜艳影响阅读时调高；想看到更多壁纸时调低",

        // About
        ["about.title"] = "关于",
        ["about.subtitle"] = "应用信息",
        ["about.app.header"] = "MC Controller",
        ["about.app.tagline"] = "把手机变成 Java 版 Minecraft 的触屏控制器",
        ["about.version.header"] = "版本",
        ["about.author.header"] = "开发者",
        ["about.author.value"] = "Linloir",
        ["about.love.header"] = "项目说明",
        ["about.love.body"] = "一个为自己写的工具，希望也能让你在沙发上更舒服地玩 Minecraft。",
    };

    private static readonly Dictionary<string, string> EnUs = new()
    {
        ["app.title"] = "MC Controller",
        ["app.tooltip"] = "MC Controller",

        ["tray.open"] = "Open Panel",
        ["tray.exit"] = "Exit Service",

        ["nav.root"] = "Mobile Controller",
        ["nav.discovery"] = "Devices",
        ["nav.settings"] = "Settings",
        ["nav.global"] = "Preferences",
        ["nav.about"] = "About",

        ["discovery.title"] = "Devices",
        ["discovery.subtitle"] = "Pick a USB or LAN device to use as a controller",
        ["discovery.status.section"] = "Status",
        ["discovery.status.header"] = "Current connection",
        ["discovery.status.waiting"] = "Waiting for a phone...",
        ["discovery.status.connected"] = "Connected: {0}",
        ["discovery.pill.connected"] = "Connected",
        ["discovery.pill.disconnected"] = "Idle",
        ["discovery.usb.section"] = "USB",
        ["discovery.usb.empty.header"] = "Plug in a phone via USB",
        ["discovery.usb.empty.desc"] = "Connect a phone with USB debugging enabled — once detected, we'll auto-run adb reverse to forward port 34555 so the phone can connect to 127.0.0.1.",
        ["discovery.usb.appInstalled"] = "App installed",
        ["discovery.lan.section"] = "LAN",
        ["discovery.lan.header"] = "Broadcasting our address",
        ["discovery.lan.desc"] = "We send an ANNOUNCE packet to UDP 34556 every second. The phone's connect screen will list this PC automatically.",
        ["discovery.net.section"] = "This computer",
        ["discovery.net.header"] = "Local IP addresses",
        ["discovery.net.desc"] = "Type any of these into the phone for the WiFi-mode connect screen",

        ["settings.title"] = "Settings",
        ["settings.subtitle"] = "Service, profiles, and the look curve",
        ["settings.service.section"] = "Service",
        ["settings.service.port.header"] = "Server port",
        ["settings.service.port.listening"] = "Listening...",
        ["settings.profile.section"] = "Profiles",
        ["settings.profile.current.header"] = "Active profile",
        ["settings.profile.current.desc"] = "Swap between sensitivity / curve / deadzone presets",
        ["settings.profile.name.header"] = "Profile name",
        ["settings.profile.name.desc"] = "Cosmetic only",
        ["settings.profile.manage.header"] = "Manage profiles",
        ["settings.profile.manage.desc"] = "Create, duplicate, restore, or remove the current profile",
        ["settings.profile.new"] = "New",
        ["settings.profile.duplicate"] = "Duplicate",
        ["settings.profile.restore"] = "Restore defaults",
        ["settings.profile.delete"] = "Delete",
        ["settings.profile.delete.confirm"] = "Delete profile “{0}”?",
        ["settings.profile.delete.title"] = "Delete profile",
        ["settings.profile.restore.confirm"] = "Reset “{0}”'s sensitivity, curve, and deadzone to defaults?",
        ["settings.profile.restore.title"] = "Restore defaults",
        ["settings.profile.atLeastOne"] = "Keep at least one profile",
        ["settings.profile.newName"] = "New profile {0}",
        ["settings.camera.section"] = "Look",
        ["settings.camera.sensitivity.header"] = "Sensitivity",
        ["settings.camera.sensitivity.desc"] = "Overall mouse-move multiplier (turn off “Enhance pointer precision” in Windows first)",
        ["settings.camera.curve.header"] = "Curve (advanced)",
        ["settings.camera.curve.desc"] = "Linear is just slope; Power adds an acceleration curve on top of sensitivity",
        ["settings.camera.curve.type"] = "Curve type",
        ["settings.camera.curve.linear"] = "Linear",
        ["settings.camera.curve.power"] = "Power",
        ["settings.camera.curve.factor"] = "Accel strength",
        ["settings.camera.curve.exp"] = "Accel exponent",
        ["settings.camera.curve.maxmul"] = "Max multiplier",
        ["settings.camera.curve.preview"] = "Live preview",
        ["settings.camera.curve.legend.curve"] = "Current curve (sensitivity × accel)",
        ["settings.camera.curve.legend.ref"] = "y = x reference (no scaling)",
        ["settings.movement.section"] = "Movement",
        ["settings.movement.deadzone.header"] = "Dead zone",
        ["settings.movement.deadzone.desc"] = "Stick range that gets ignored at center",
        ["settings.movement.enter.header"] = "Enter threshold",
        ["settings.movement.enter.desc"] = "Magnitude that starts pressing a WASD key",
        ["settings.movement.exit.header"] = "Exit threshold",
        ["settings.movement.exit.desc"] = "Magnitude that releases the WASD key (must be < enter, gives hysteresis)",
        ["settings.save.saved"] = "Saved",
        ["settings.save.failed"] = "Save failed: {0}",
        ["settings.dialog.ok"] = "OK",
        ["settings.dialog.cancel"] = "Cancel",

        ["global.title"] = "Preferences",
        ["global.subtitle"] = "Settings that affect the whole app, across all profiles",
        ["global.section.general"] = "General",
        ["global.startup.header"] = "Run at Windows startup",
        ["global.startup.desc"] = "Quietly start in the background after you sign in; the tray icon stays available",
        ["global.section.appearance"] = "Appearance",
        ["global.transparency.header"] = "Enable transparency",
        ["global.transparency.desc"] = "Use Acrylic blur for the window background; turn off for a solid color",
        ["global.chrome.header"] = "Sidebar + title bar opacity",
        ["global.chrome.desc"] = "0% = fully transparent (pure Acrylic); 100% = wallpaper fully hidden",
        ["global.content.header"] = "Content area opacity",
        ["global.content.desc"] = "Raise it when a vibrant wallpaper hurts readability; lower it to see more wallpaper",

        ["about.title"] = "About",
        ["about.subtitle"] = "App info",
        ["about.app.header"] = "MC Controller",
        ["about.app.tagline"] = "Turn your phone into a touchscreen controller for Java Edition Minecraft",
        ["about.version.header"] = "Version",
        ["about.author.header"] = "Author",
        ["about.author.value"] = "Linloir",
        ["about.love.header"] = "Notes",
        ["about.love.body"] = "Built for my own couch-gaming setup. Hope it makes your Minecraft sessions a bit more comfortable too.",
    };
}
