import { REPOSITORY_URL } from "./i18n";

export const APP_VERSION = "1.0.1";

const RELEASE_BASE = `${REPOSITORY_URL}/releases/download/v${APP_VERSION}`;
// Tencent COS bucket bound to dl.couchmc.linloir.cn. APK / EXE / DMG are
// blocked on the default COS domain, so this custom domain is what makes
// the high-speed mirror legal. HTTPS is required because the site is
// served over HTTPS — make sure the SSL cert is configured on the COS
// custom-domain side, otherwise modern browsers will silently block the
// download as mixed content.
const COS_BASE = `https://dl.couchmc.linloir.cn/couchmc`;

export type PlatformKey = "windows" | "macos" | "android" | "ios";

export type PlatformDownload = {
  key: PlatformKey;
  filename: string | null;
  size: string;
  cosUrl: string | null;
  githubUrl: string | null;
  appStoreUrl: string | null;
};

export const DOWNLOADS: Record<PlatformKey, PlatformDownload> = {
  windows: {
    key: "windows",
    filename: `CouchMC-Setup-${APP_VERSION}.exe`,
    size: "46 MB",
    cosUrl: `${COS_BASE}/CouchMC-Setup-${APP_VERSION}.exe`,
    githubUrl: `${RELEASE_BASE}/CouchMC-Setup-${APP_VERSION}.exe`,
    appStoreUrl: null,
  },
  macos: {
    key: "macos",
    filename: `CouchMC-${APP_VERSION}.dmg`,
    size: "14 MB",
    cosUrl: `${COS_BASE}/CouchMC-${APP_VERSION}.dmg`,
    githubUrl: `${RELEASE_BASE}/CouchMC-${APP_VERSION}.dmg`,
    appStoreUrl: null,
  },
  android: {
    key: "android",
    filename: `CouchMC-${APP_VERSION}.apk`,
    size: "7 MB",
    cosUrl: `${COS_BASE}/CouchMC-${APP_VERSION}.apk`,
    githubUrl: `${RELEASE_BASE}/CouchMC-${APP_VERSION}.apk`,
    appStoreUrl: null,
  },
  ios: {
    key: "ios",
    filename: null,
    size: "",
    cosUrl: null,
    // Points at the ios/ source folder rather than a release binary: iOS
    // doesn't ship a sideload artefact, so the GitHub button is "clone &
    // build yourself" for developers who want the source.
    githubUrl: `${REPOSITORY_URL}/tree/master/ios`,
    appStoreUrl: "https://apps.apple.com/cn/app/couchmc/id6768538710",
  },
};
