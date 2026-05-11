import Foundation

/// Minimal i18n lookup. Mirrors the WinUI `Util/L.cs` table. We use a
/// hand-rolled dictionary (vs. `.strings` files) for parity with the
/// Windows side and to keep the active language obvious to anyone
/// reading either codebase. Strings are addressed by dot-separated keys.
enum L {

    /// Returns the localized string for `key`, or `fallback` if the key
    /// is missing. `fallback` is also the developer reference string.
    static func get(_ key: String, fallback: String = "") -> String {
        if let v = active[key], !v.isEmpty { return v }
        return fallback
    }

    static let activeLanguageTag: String = {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let lang = Locale.Language(identifier: preferred)
        return (lang.languageCode?.identifier ?? "en").lowercased()
    }()

    private static let active: [String: String] = pick()

    private static func pick() -> [String: String] {
        switch activeLanguageTag {
        case "zh": return zhHans
        default:   return enUs
        }
    }

    // MARK: - ZH-Hans

    private static let zhHans: [String: String] = [
        // App
        "app.title": "MC Controller",
        "app.tooltip": "MC Controller",

        // Menu bar
        "tray.open": "打开面板",
        "tray.exit": "退出服务",

        // Navigation
        "nav.root": "移动控制器",
        "nav.discovery": "设备发现",
        "nav.settings": "设置",
        "nav.global": "全局设置",
        "nav.about": "关于",

        // Discovery
        "discovery.title": "设备发现",
        "discovery.subtitle": "发现可用的 USB 与局域网设备并选作控制器",
        "discovery.status.section": "状态",
        "discovery.status.header": "当前连接",
        "discovery.status.waiting": "等待连接...",
        "discovery.status.connected": "已连接：%@",
        "discovery.pill.connected": "已连接",
        "discovery.pill.disconnected": "未连接",
        "discovery.usb.section": "USB 设备",
        "discovery.usb.auto": "检测到 USB 设备后自动通过 adb reverse 转发端口 %@，手机直接连接 127.0.0.1 即可。",
        "discovery.usb.empty": "未检测到 USB 设备 · 请用数据线连接手机并开启 USB 调试",
        "discovery.usb.emptyTitle": "未检测到 USB 设备",
        "discovery.usb.emptyDesc": "请用数据线连接手机并打开「开发者选项 → USB 调试」",
        "discovery.status.endpoint": "对端地址",
        "discovery.status.port": "监听端口",
        "discovery.usb.appInstalled": "已安装 App",
        "discovery.usb.adbMissing": "未找到内置 adb · 请通过「打开 platform-tools」放入二进制",
        "discovery.lan.section": "局域网设备",
        "discovery.lan.header": "正在向局域网广播服务地址",
        "discovery.lan.header.short": "已在局域网公告 · 手机连接界面会自动列出本机",
        "discovery.lan.emptyTitle": "暂无局域网设备连接",
        "discovery.lan.emptyDesc": "应用已向局域网公告，手机连接界面会自动列出本机",
        "discovery.menubar.section": "菜单栏",
        "discovery.menubar.hiddenTitle": "菜单栏图标已被隐藏",
        "discovery.menubar.hiddenDesc": "%@ 正在隐藏 MC Controller 的菜单栏图标。请点击它自己的折叠箭头展开，或在它的偏好里把 MC Controller 移到「常显」分组。",
        "discovery.menubar.unknownManager": "某个菜单栏管理工具",
        "discovery.lan.desc": "每秒向 UDP 34556 广播 ANNOUNCE 包，手机端连接界面会自动列出本机。",
        "discovery.net.section": "本机网络",
        "discovery.net.header": "本机 IP 地址",
        "discovery.net.desc": "在手机端输入其中一个作为服务端地址（WiFi 模式）",
        "discovery.permission.section": "权限",
        "discovery.permission.header": "辅助功能权限",
        "discovery.permission.desc": "macOS 需要授予「辅助功能」权限才能向系统注入键盘与鼠标事件。",
        "discovery.permission.descStale": "若系统设置里已勾选但应用仍提示未授权：点「重置」清空旧的 TCC 记录（开发构建每次重新编译 cdhash 都会变，让旧授权失效），然后在系统设置里重新允许 MC Controller。",
        "discovery.permission.granted": "已授权",
        "discovery.permission.missing": "未授权 · 点击「打开系统设置」前往",
        "discovery.permission.open": "打开系统设置",
        "discovery.permission.reset": "重置授权",

        // Settings
        "settings.title": "设置",
        "settings.subtitle": "服务、配置方案与视角曲线",
        "settings.service.section": "服务",
        "settings.service.port.header": "服务端口",
        "settings.service.port.listening": "服务正在监听...",
        "settings.profile.section": "配置方案",
        "settings.profile.current.header": "当前方案",
        "settings.profile.current.desc": "切换不同的灵敏度、曲线与死区组合",
        "settings.profile.name.header": "方案名称",
        "settings.profile.name.desc": "仅作显示用",
        "settings.profile.manage.header": "方案管理",
        "settings.profile.manage.desc": "新建、复制、删除或恢复当前方案",
        "settings.profile.new": "新建",
        "settings.profile.duplicate": "复制",
        "settings.profile.restore": "恢复默认",
        "settings.profile.delete": "删除",
        "settings.profile.delete.confirm": "确定要删除「%@」？",
        "settings.profile.delete.title": "删除配置方案",
        "settings.profile.restore.confirm": "将当前方案「%@」的灵敏度、曲线与死区参数重置为默认值？",
        "settings.profile.restore.title": "恢复默认设置",
        "settings.profile.atLeastOne": "至少保留一个方案",
        "settings.profile.newName": "新方案 %d",
        "settings.camera.section": "视角",
        "settings.camera.sensitivity.header": "灵敏度",
        "settings.camera.sensitivity.desc": "鼠标移动的整体放大倍率（建议先关闭系统「鼠标」偏好里的指针加速）",
        "settings.camera.curve.header": "曲线（高级）",
        "settings.camera.curve.desc": "Linear 仅受灵敏度控制；Power 在此基础上叠加加速曲线",
        "settings.camera.curve.type": "曲线类型",
        "settings.camera.curve.linear": "Linear（线性）",
        "settings.camera.curve.power": "Power（带加速）",
        "settings.camera.curve.factor": "加速强度",
        "settings.camera.curve.exp": "加速指数",
        "settings.camera.curve.maxmul": "最大放大倍率",
        "settings.camera.curve.preview": "实时预览",
        "settings.camera.curve.legend.curve": "当前曲线（灵敏度 × 加速）",
        "settings.camera.curve.legend.ref": "y = x 参考线（无放大基准）",
        "settings.movement.section": "移动",
        "settings.movement.deadzone.header": "死区",
        "settings.movement.deadzone.desc": "摇杆中心忽略的范围",
        "settings.movement.enter.header": "进入阈值",
        "settings.movement.enter.desc": "开始按下方向键的阈值",
        "settings.movement.exit.header": "退出阈值",
        "settings.movement.exit.desc": "松开方向键的阈值（须小于进入阈值，提供滞回）",
        "settings.save.saved": "已保存",
        "settings.save.failed": "保存失败：%@",

        // Global settings
        "global.title": "全局设置",
        "global.subtitle": "影响整个应用的行为，跨配置方案生效",
        "global.section.general": "通用",
        "global.startup.header": "开机时启动",
        "global.startup.desc": "登录 macOS 后在后台自动运行，菜单栏图标常驻待机",
        "global.section.appearance": "外观",
        "global.liquidGlass.header": "Liquid Glass 设计语言",
        "global.liquidGlass.desc": "macOS 26 引入的玻璃材质效果；在更早系统上自动回落为传统毛玻璃",
        "global.liquidGlass.unsupported": "当前系统不支持 Liquid Glass（需要 macOS 26 Tahoe 或更高）。",

        // About
        "about.title": "关于",
        "about.subtitle": "应用信息",
        "about.app.header": "MC Controller",
        "about.app.tagline": "把手机变成 Java 版 Minecraft 的触屏控制器",
        "about.version.header": "版本",
        "about.author.header": "开发者",
        "about.author.value": "Linloir",
        "about.love.header": "项目说明",
        "about.love.body": "一个为自己写的工具，希望也能让你在沙发上更舒服地玩 Minecraft。",
    ]

    // MARK: - EN-US

    private static let enUs: [String: String] = [
        "app.title": "MC Controller",
        "app.tooltip": "MC Controller",

        "tray.open": "Open Panel",
        "tray.exit": "Quit Service",

        "nav.root": "Mobile Controller",
        "nav.discovery": "Devices",
        "nav.settings": "Settings",
        "nav.global": "Preferences",
        "nav.about": "About",

        "discovery.title": "Devices",
        "discovery.subtitle": "Pick a USB or LAN device to use as a controller",
        "discovery.status.section": "Status",
        "discovery.status.header": "Current connection",
        "discovery.status.waiting": "Waiting for a phone...",
        "discovery.status.connected": "Connected: %@",
        "discovery.pill.connected": "Connected",
        "discovery.pill.disconnected": "Idle",
        "discovery.usb.section": "USB",
        "discovery.usb.auto": "We auto-run `adb reverse` on every connected device so the phone can reach this Mac at 127.0.0.1 — no manual setup needed. (Bundled adb on port %@.)",
        "discovery.usb.empty": "No USB device detected · plug in a phone with USB debugging enabled",
        "discovery.usb.emptyTitle": "No USB device detected",
        "discovery.usb.emptyDesc": "Plug in a phone with USB debugging enabled",
        "discovery.status.endpoint": "Endpoint",
        "discovery.status.port": "Listening port",
        "discovery.usb.appInstalled": "App installed",
        "discovery.usb.adbMissing": "Bundled adb missing — drop the binary into Resources/adb",
        "discovery.lan.section": "LAN",
        "discovery.lan.header": "Broadcasting our address",
        "discovery.lan.header.short": "Announcing on the local network · the phone's connect screen lists this Mac automatically",
        "discovery.lan.emptyTitle": "No LAN device connected yet",
        "discovery.lan.emptyDesc": "We're broadcasting on the local network; the phone's connect screen will list this Mac.",
        "discovery.menubar.section": "Menu bar",
        "discovery.menubar.hiddenTitle": "Menu bar icon hidden",
        "discovery.menubar.hiddenDesc": "%@ is hiding MC Controller's menu bar icon. Reveal it by clicking the manager's overflow chevron, or open the manager's preferences and move MC Controller into the always-visible group.",
        "discovery.menubar.unknownManager": "A menu bar manager",
        "discovery.lan.desc": "We send an ANNOUNCE packet to UDP 34556 every second.",
        "discovery.net.section": "This computer",
        "discovery.net.header": "Local IP addresses",
        "discovery.net.desc": "Type any of these into the phone for the WiFi-mode connect screen",
        "discovery.permission.section": "Permission",
        "discovery.permission.header": "Accessibility permission",
        "discovery.permission.desc": "macOS requires Accessibility permission for the app to post keyboard and mouse events.",
        "discovery.permission.descStale": "If System Settings shows MC Controller as allowed but this prompt still appears, click Reset to clear the stale TCC entry — rebuilds change the binary's cdhash and invalidate the previous grant. After reset, re-authorize MC Controller in System Settings.",
        "discovery.permission.granted": "Granted",
        "discovery.permission.missing": "Not granted · open System Settings to allow",
        "discovery.permission.open": "Open System Settings",
        "discovery.permission.reset": "Reset",

        "settings.title": "Settings",
        "settings.subtitle": "Service, profiles, and the look curve",
        "settings.service.section": "Service",
        "settings.service.port.header": "Server port",
        "settings.service.port.listening": "Listening...",
        "settings.profile.section": "Profiles",
        "settings.profile.current.header": "Active profile",
        "settings.profile.current.desc": "Swap between sensitivity / curve / deadzone presets",
        "settings.profile.name.header": "Profile name",
        "settings.profile.name.desc": "Cosmetic only",
        "settings.profile.manage.header": "Manage profiles",
        "settings.profile.manage.desc": "Create, duplicate, restore, or remove the current profile",
        "settings.profile.new": "New",
        "settings.profile.duplicate": "Duplicate",
        "settings.profile.restore": "Restore defaults",
        "settings.profile.delete": "Delete",
        "settings.profile.delete.confirm": "Delete profile “%@”?",
        "settings.profile.delete.title": "Delete profile",
        "settings.profile.restore.confirm": "Reset “%@”'s sensitivity, curve, and deadzone to defaults?",
        "settings.profile.restore.title": "Restore defaults",
        "settings.profile.atLeastOne": "Keep at least one profile",
        "settings.profile.newName": "New profile %d",
        "settings.camera.section": "Look",
        "settings.camera.sensitivity.header": "Sensitivity",
        "settings.camera.sensitivity.desc": "Overall mouse-move multiplier (disable pointer acceleration in System Settings → Mouse first)",
        "settings.camera.curve.header": "Curve (advanced)",
        "settings.camera.curve.desc": "Linear is just slope; Power adds an acceleration curve on top of sensitivity",
        "settings.camera.curve.type": "Curve type",
        "settings.camera.curve.linear": "Linear",
        "settings.camera.curve.power": "Power",
        "settings.camera.curve.factor": "Accel strength",
        "settings.camera.curve.exp": "Accel exponent",
        "settings.camera.curve.maxmul": "Max multiplier",
        "settings.camera.curve.preview": "Live preview",
        "settings.camera.curve.legend.curve": "Current curve (sensitivity × accel)",
        "settings.camera.curve.legend.ref": "y = x reference (no scaling)",
        "settings.movement.section": "Movement",
        "settings.movement.deadzone.header": "Dead zone",
        "settings.movement.deadzone.desc": "Stick range that gets ignored at center",
        "settings.movement.enter.header": "Enter threshold",
        "settings.movement.enter.desc": "Magnitude that starts pressing a WASD key",
        "settings.movement.exit.header": "Exit threshold",
        "settings.movement.exit.desc": "Magnitude that releases the WASD key (must be < enter, gives hysteresis)",
        "settings.save.saved": "Saved",
        "settings.save.failed": "Save failed: %@",

        "global.title": "Preferences",
        "global.subtitle": "Settings that affect the whole app, across all profiles",
        "global.section.general": "General",
        "global.startup.header": "Launch at login",
        "global.startup.desc": "Run quietly in the background after you sign in; the menu bar item stays available",
        "global.section.appearance": "Appearance",
        "global.liquidGlass.header": "Liquid Glass design",
        "global.liquidGlass.desc": "macOS 26's glass material; older systems automatically fall back to standard translucency",
        "global.liquidGlass.unsupported": "This macOS doesn't support Liquid Glass yet (requires macOS 26 Tahoe or later).",

        "about.title": "About",
        "about.subtitle": "App info",
        "about.app.header": "MC Controller",
        "about.app.tagline": "Turn your phone into a touchscreen controller for Java Edition Minecraft",
        "about.version.header": "Version",
        "about.author.header": "Author",
        "about.author.value": "Linloir",
        "about.love.header": "Notes",
        "about.love.body": "Built for my own couch-gaming setup. Hope it makes your Minecraft sessions a bit more comfortable too.",
    ]
}
