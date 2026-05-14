import { REPOSITORY_URL } from "./i18n";

export const APP_VERSION = "1.0.1";

const RELEASE_BASE = `${REPOSITORY_URL}/releases/download/v${APP_VERSION}`;

export type PlatformKey = "windows" | "macos" | "android" | "ios";

export type PlatformDownload = {
  key: PlatformKey;
  filename: string | null;
  size: string;
  cosUrl: string | null;
  githubUrl: string | null;
  appStoreUrl: string | null;
};

// COS URLs are placeholders — replace with the real CDN endpoints when
// they're provisioned. The GitHub URLs auto-resolve through any future
// repo rename redirects.
export const DOWNLOADS: Record<PlatformKey, PlatformDownload> = {
  windows: {
    key: "windows",
    filename: `CouchMC-Setup-${APP_VERSION}.exe`,
    size: "46 MB",
    cosUrl: `https://cos.couchmc.app/releases/v${APP_VERSION}/CouchMC-Setup-${APP_VERSION}.exe`,
    githubUrl: `${RELEASE_BASE}/CouchMC-Setup-${APP_VERSION}.exe`,
    appStoreUrl: null,
  },
  macos: {
    key: "macos",
    filename: `CouchMC-${APP_VERSION}.dmg`,
    size: "14 MB",
    cosUrl: `https://cos.couchmc.app/releases/v${APP_VERSION}/CouchMC-${APP_VERSION}.dmg`,
    githubUrl: `${RELEASE_BASE}/CouchMC-${APP_VERSION}.dmg`,
    appStoreUrl: null,
  },
  android: {
    key: "android",
    filename: `CouchMC-${APP_VERSION}.apk`,
    size: "7 MB",
    cosUrl: `https://cos.couchmc.app/releases/v${APP_VERSION}/CouchMC-${APP_VERSION}.apk`,
    githubUrl: `${RELEASE_BASE}/CouchMC-${APP_VERSION}.apk`,
    appStoreUrl: null,
  },
  ios: {
    key: "ios",
    filename: null,
    size: "",
    cosUrl: null,
    githubUrl: null,
    // Empty string means "not yet available" — the page surfaces a pending state.
    appStoreUrl: "",
  },
};
