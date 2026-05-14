export const REPOSITORY_URL = "https://github.com/Linloir/mc-controller";
export const ISSUES_URL = `${REPOSITORY_URL}/issues`;
export const PROFILE_URL = "https://github.com/Linloir";
export const RELEASES_URL = `${REPOSITORY_URL}/releases`;
export const APP_STORE_URL = "";

export type Language = "en" | "zh";

export const translations = {
  en: {
    meta: {
      title: "CouchMC - Bring Minecraft to Couch",
      description:
        "CouchMC turns your phone into a touchscreen controller for Minecraft Java Edition.",
    },
    common: {
      brand: "CouchMC",
      nav: {
        home: "Home",
        download: "Download",
        github: "Github",
        about: "About",
        privacy: "Privacy",
      },
      theme: {
        label: "Theme",
        system: "System",
        light: "Light",
        dark: "Dark",
      },
      language: {
        label: "Language",
        value: "EN",
      },
      downloadNow: "Download Now",
      repository: "Repository",
      githubIssues: "GitHub Issues",
      profile: "GitHub Profile",
    },
    home: {
      eyebrow: "Play Anywhere",
      titleGreen: "Bring Minecraft",
      titleWhite: "to Couch",
      copy:
        "Enjoy a seamless Minecraft experience on any Java edition, on your couch. No keyboard, no controller, no mods - just pure fun.",
      featuresTitle: "Mobile controls, made for Minecraft.",
      features: [
        {
          title: "Same Wi-Fi, you're in.",
          copy:
            "Drop the phone and the PC onto the same network. CouchMC finds the server for you, no IP to type.",
          alt: "Phone showing a list of saved and discovered CouchMC hosts on the local network",
        },
        {
          title: "Every button, tuned for Minecraft.",
          copy:
            "Sprint toggle, hotbar swipe, drop, off-hand — every common action has its own button. Keys are remappable, and every threshold dials in to taste.",
          alt: "Settings screen showing layout editor entries and snap toggles for fine-grained controller tuning",
        },
        {
          title: "Zero learning curve.",
          copy:
            "Stick, look pad, hotbar — they work the way you already expect from mobile games. First match in, you're playing.",
          alt: "In-game controller layout with joystick, look pad, and hotbar overlaid on a Minecraft scene",
        },
      ],
      cta: {
        title: "Pick your platform.",
        copy: "Windows or Mac on the desk, Android or iOS in hand. Grab the matching pair and play.",
        button: "Go to downloads",
      },
    },
    download: {
      title: "Pick your platform.",
      lede:
        "Two sources per platform — pick whichever is faster from where you are. Both contain the same build.",
      version: "v{version}",
      role: {
        server: "Server (PC)",
        client: "Client (phone)",
      },
      platforms: {
        windows: {
          name: "Windows",
          requirement: "Windows 10 1809+",
        },
        macos: {
          name: "macOS",
          requirement: "macOS 14 Sonoma+",
        },
        android: {
          name: "Android",
          requirement: "Android 8.0+",
        },
        ios: {
          name: "iOS",
          requirement: "iOS 16+",
        },
      },
      buttons: {
        cos: "Fast download",
        cosHint: "via global CDN",
        github: "GitHub release",
        githubHint: "official mirror",
        appStore: "App Store",
        appStoreHint: "iOS app marketplace",
        appStorePending: "Pending review",
        appStorePendingHint: "We'll enable this when Apple approves the build.",
      },
    },
    about: {
      eyebrow: "About the project",
      title: "Playing MC from the couch has never been this simple.",
      intro:
        "I started building CouchMC after moving into a new home, buying a big TV, and setting up the couch. After work, I often wanted to turn off the lights, open Minecraft, and spend a short while inside that relaxed, free world.",
      story: [
        "The problem was that there was no comfortable way to do it. A mouse and keyboard on the couch broke the immersion almost immediately. A controller sounded reasonable, so I spent a night trying launchers and controller mods, but the experience still felt rough. Camera movement felt like turning an aircraft carrier, the buttons were easy to mix up, and switching hotbar items never became natural.",
        "That was when I realized I did not want another thing to learn. I play games to relax, not to spend another evening training muscle memory. CouchMC exists for people who are already used to mobile MOBA or FPS controls: install the desktop app and the phone app, stay on the same LAN, and start playing. No controller, no mod research, no strange camera feel - just let the fun return to the game itself.",
      ],
      authorTitle: "Author",
      authorName: "Linloir",
      authorRole: "Independent developer and maintainer of CouchMC.",
      authorCopy:
        "I like trying to build all kinds of interesting things, especially when a real need shows up in my own life. If I cannot find the tool I want, I usually end up making it myself - like CouchMC, the project you are looking at now. I care a lot about whether software feels clean, useful, and a little delightful. If that kind of work interests you, feel free to follow me on GitHub.",
      contactsCopy:
        "For bugs, feature requests, privacy questions, or App Store review follow-up, please use the public repository or GitHub Issues.",
    },
    privacy: {
      eyebrow: "Privacy Policy",
      title: "CouchMC Privacy Policy",
      effective: "Effective date: May 13, 2026",
      intro:
        "This policy explains how CouchMC handles information when you use the mobile client and desktop server. It is written to support App Store review and to be clear about the project's local-first design.",
      sections: [
        {
          title: "Information we collect",
          body: [
            "CouchMC does not require an account, does not collect names, email addresses, payment information, contacts, photos, precise location, advertising identifiers, or health data.",
            "The app may process local network information needed to discover and connect to a CouchMC desktop server, such as IP addresses, ports, device names, connection status, and latency diagnostics. This information is used only for local connectivity and troubleshooting.",
            "Controller input events, such as touch gestures, button presses, joystick movement, and look deltas, are transmitted only to the desktop server you connect to.",
          ],
        },
        {
          title: "How information is used",
          body: [
            "Local network data is used to find your desktop server, maintain the controller session, display connection state, and improve responsiveness.",
            "Input events are used by the desktop server to generate local keyboard and mouse actions for Minecraft Java Edition.",
            "CouchMC does not sell, rent, or share personal information for advertising or cross-app tracking.",
          ],
        },
        {
          title: "Storage and retention",
          body: [
            "App preferences, such as layout profiles and connection settings, may be stored locally on your device or computer.",
            "CouchMC does not operate a cloud service for storing user profiles or gameplay data. Locally stored settings remain on your devices until you delete the app, reset settings, or remove the files.",
          ],
        },
        {
          title: "Third parties",
          body: [
            "CouchMC does not include third-party advertising SDKs or analytics SDKs.",
            "If you visit GitHub links from this website or the project, GitHub's own privacy practices apply to that website.",
          ],
        },
        {
          title: "Children's privacy",
          body: [
            "CouchMC is a controller utility and is not designed to knowingly collect personal information from children.",
            "If you believe a child has provided personal information through a related support channel, contact the maintainer so it can be removed.",
          ],
        },
        {
          title: "Security",
          body: [
            "CouchMC is designed for trusted local networks. You should only connect to desktop servers you recognize and trust.",
            "Keep your devices and operating systems updated, and avoid using the app on untrusted public networks.",
          ],
        },
        {
          title: "Changes to this policy",
          body: [
            "This policy may be updated when the app adds new capabilities or platform requirements change.",
            "Material changes will be reflected on this page with an updated effective date.",
          ],
        },
        {
          title: "Contact",
          body: [
            "For privacy questions, App Store review questions, or data removal requests related to project support, contact the maintainer through GitHub Issues.",
          ],
        },
      ],
    },
  },
  zh: {
    meta: {
      title: "CouchMC - 把 Minecraft 带到沙发上",
      description: "CouchMC 将你的手机变成 Minecraft Java 版的触屏控制器。",
    },
    common: {
      brand: "CouchMC",
      nav: {
        home: "首页",
        download: "下载",
        github: "Github",
        about: "关于",
        privacy: "隐私",
      },
      theme: {
        label: "主题",
        system: "跟随系统",
        light: "浅色",
        dark: "深色",
      },
      language: {
        label: "语言",
        value: "中",
      },
      downloadNow: "立即下载",
      repository: "代码仓库",
      githubIssues: "GitHub Issues",
      profile: "GitHub 主页",
    },
    home: {
      eyebrow: "随处游玩",
      titleGreen: "把 Minecraft",
      titleWhite: "带到沙发上",
      copy:
        "在沙发上畅玩 Minecraft Java 版。不需要键盘，不需要手柄，也不需要安装 Mod - 打开就能玩。",
      featuresTitle: "专为 MC 优化的移动操作体验",
      features: [
        {
          title: "连上同一个 Wi-Fi 就行。",
          copy:
            "把电脑和手机连进同一个局域网，CouchMC 会自动发现服务端，不用输 IP，点一下就开始。",
          alt: "手机展示局域网内已保存与已发现的 CouchMC 主机列表",
        },
        {
          title: "每个按钮都为 MC 调过。",
          copy:
            "快速疾跑、物品栏滑切、丢弃、副手都有专属按钮，键位可改，每个阈值都能逐项自定义。",
          alt: "设置页展示布局编辑入口与各类吸附开关",
        },
        {
          title: "0 上手成本。",
          copy:
            "摇杆、视角、热键栏的手感沿用手机游戏的肌肉记忆，第一局就能找到节奏。",
          alt: "游戏内的摇杆、视角板与物品栏覆盖在 Minecraft 场景上",
        },
      ],
      cta: {
        title: "挑选你的平台。",
        copy: "桌面端选 Windows 或 Mac，手持端选 Android 或 iOS，搭配下载即可开始。",
        button: "前往下载页",
      },
    },
    download: {
      title: "挑选你的平台。",
      lede:
        "每个平台都提供两个下载源，从你所在的位置挑更快的那一个。两边的安装包内容完全一致。",
      version: "v{version}",
      role: {
        server: "桌面服务端",
        client: "手机客户端",
      },
      platforms: {
        windows: {
          name: "Windows",
          requirement: "Windows 10 1809+",
        },
        macos: {
          name: "macOS",
          requirement: "macOS 14 Sonoma+",
        },
        android: {
          name: "Android",
          requirement: "Android 8.0+",
        },
        ios: {
          name: "iOS",
          requirement: "iOS 16+",
        },
      },
      buttons: {
        cos: "高速下载",
        cosHint: "国内 CDN",
        github: "GitHub 仓库",
        githubHint: "官方镜像",
        appStore: "App Store",
        appStoreHint: "iOS 应用商店",
        appStorePending: "暂未上架",
        appStorePendingHint: "上架后会自动放出此按钮。",
      },
    },
    about: {
      eyebrow: "关于项目",
      title: "沙发上玩 MC 从未如此简单",
      intro:
        "我最初想做这个 App，是因为刚搬到新家，买了一个大电视，也终于有了一张舒服的沙发。很多时候下班回到家，我只想关上灯，打开游戏，短暂地沉浸在 Minecraft 带来的放松和自由里。",
      story: [
        "但当时没有这样一款软件。想在沙发上玩 MC，要么别扭地抱着鼠标键盘，要么买手柄、装插件。我一开始选择了前者，但很快发现那个姿势完全破坏了沉浸感。后来我买了手柄，花了一晚上折腾 Launcher 和各种大家推荐的手柄 MOD，结果体验依然很灾难。光是视角转动就像大家玩梗说的“航母掉头”，我甚至花了十几分钟都没能流畅地打死一只羊。",
        "更麻烦的是，手柄键位总是不够用，我还经常记混跳跃和攻击，也没办法很自然地切换工具栏物品。折腾了一晚上之后，我很快放弃了：我玩游戏是为了放松，不是为了再掌握一个需要训练的新任务。所以 CouchMC 的初衷很简单，让习惯手机 MOBA 或 FPS 操作的玩家，可以零成本地切回 MC：不研究 MOD，不买手柄，不适应奇怪的按键和视角，只要下载电脑端和手机端，在同一个局域网里就能开始玩。",
      ],
      authorTitle: "作者",
      authorName: "Linloir",
      authorRole: "CouchMC 的独立开发者与维护者。",
      authorCopy:
        "我是 Linloir。我喜欢尝试构建各种有趣的东西，尤其是当生活里真的出现某个需求，而我又找不到足够顺手的工具时，我通常就会忍不住自己把它做出来，就像你现在看到的 CouchMC 一样。比起单纯堆功能，我更在意一个东西是不是真的好用、是不是少一点折腾、交互和设计有没有让人舒服一点。如果你也喜欢这类项目，欢迎在 GitHub 上关注我。",
      contactsCopy:
        "如果你想反馈 Bug、提出功能建议、咨询隐私问题或处理 App Store 审核沟通，请通过公开仓库或 GitHub Issues 联系。",
    },
    privacy: {
      eyebrow: "隐私政策",
      title: "CouchMC 隐私政策",
      effective: "生效日期：2026 年 5 月 13 日",
      intro:
        "本政策说明你使用 CouchMC 移动端和桌面服务端时，项目如何处理信息。内容面向 App Store 审核要求撰写，也尽量清楚说明项目的本地优先设计。",
      sections: [
        {
          title: "我们收集的信息",
          body: [
            "CouchMC 不要求注册账号，不收集姓名、邮箱、付款信息、通讯录、照片、精确位置、广告标识符或健康数据。",
            "应用可能会处理用于发现和连接 CouchMC 桌面服务端的本地网络信息，例如 IP 地址、端口、设备名称、连接状态和延迟诊断。这些信息仅用于本地连接和故障排查。",
            "触控手势、按钮按下、摇杆移动和视角移动等控制输入只会发送给你主动连接的桌面服务端。",
          ],
        },
        {
          title: "信息用途",
          body: [
            "本地网络信息用于发现桌面服务端、维持控制会话、展示连接状态并提升响应速度。",
            "输入事件由桌面服务端转换为本机键盘和鼠标动作，用于控制 Minecraft Java 版。",
            "CouchMC 不会出售、出租或为了广告、跨 App 跟踪而共享个人信息。",
          ],
        },
        {
          title: "存储与保留",
          body: [
            "布局配置、连接设置等偏好可能会保存在你的设备或电脑本地。",
            "CouchMC 不运营用于存储用户配置或游戏数据的云服务。本地设置会保留在你的设备上，直到你删除应用、重置设置或移除相关文件。",
          ],
        },
        {
          title: "第三方",
          body: [
            "CouchMC 不包含第三方广告 SDK 或分析 SDK。",
            "如果你访问本网站或项目中的 GitHub 链接，GitHub 网站自身的隐私实践将适用。",
          ],
        },
        {
          title: "儿童隐私",
          body: [
            "CouchMC 是一个控制器工具，并非设计用于有意收集儿童个人信息。",
            "如果你认为儿童通过相关支持渠道提供了个人信息，请联系维护者以便删除。",
          ],
        },
        {
          title: "安全",
          body: [
            "CouchMC 面向可信任的本地网络设计。你应只连接自己认识并信任的桌面服务端。",
            "请保持设备和操作系统更新，并避免在不可信的公共网络中使用。",
          ],
        },
        {
          title: "政策变更",
          body: [
            "当应用加入新能力或平台要求变化时，本政策可能更新。",
            "重要变更会在本页面体现，并更新生效日期。",
          ],
        },
        {
          title: "联系我们",
          body: [
            "如有隐私问题、App Store 审核问题，或与项目支持相关的数据删除请求，请通过 GitHub Issues 联系维护者。",
          ],
        },
      ],
    },
  },
} as const;

export type Translation = (typeof translations)[Language];
