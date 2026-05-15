"use client";

import { useLayoutEffect, useRef, type ReactNode, type RefObject } from "react";

import { usePreferences } from "@/components/AppPreferences";
import { APP_VERSION, DOWNLOADS, type PlatformKey } from "@/lib/downloads";

const PLATFORM_ORDER: PlatformKey[] = ["windows", "macos", "android", "ios"];
const SERVER_PLATFORMS: PlatformKey[] = ["windows", "macos"];

/** Mirrors the Home page hook — see app/page.tsx for the rationale. */
function useRevealAnimations(ref: RefObject<HTMLElement | null>, ready: boolean) {
  useLayoutEffect(() => {
    if (!ready) return;
    const root = ref.current;
    if (!root) return;
    const elements = Array.from(
      root.querySelectorAll<HTMLElement>("[data-reveal-anim]"),
    );
    if (elements.length === 0) return;
    const isFreshTopLoad = window.scrollY === 0;
    const offscreen: HTMLElement[] = [];
    elements.forEach((el) => {
      const rect = el.getBoundingClientRect();
      const belowFold = rect.top >= window.innerHeight;
      if (belowFold) {
        el.dataset.revealState = "pending";
        offscreen.push(el);
      } else if (isFreshTopLoad) {
        el.dataset.revealState = "shown";
      }
    });
    if (typeof IntersectionObserver === "undefined" || offscreen.length === 0) {
      offscreen.forEach((el) => {
        el.dataset.revealState = "shown";
      });
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting && entry.target instanceof HTMLElement) {
            entry.target.dataset.revealState = "shown";
            observer.unobserve(entry.target);
          }
        }
      },
      { threshold: 0, rootMargin: "0px 0px -4% 0px" },
    );
    offscreen.forEach((el) => observer.observe(el));
    const safetyTimer = window.setTimeout(() => {
      offscreen.forEach((el) => {
        if (el.dataset.revealState === "pending") {
          el.dataset.revealState = "shown";
        }
      });
      observer.disconnect();
    }, 10000);
    return () => {
      observer.disconnect();
      window.clearTimeout(safetyTimer);
    };
  }, [ref, ready]);
}

function PlatformIcon({ platform }: { platform: PlatformKey }) {
  switch (platform) {
    case "windows":
      return (
        <svg className="platform-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M3.5 5.4 11 4.3v7.2H3.5V5.4Zm0 13.2V11.5H11v7.2L3.5 17.6Zm8.5-7.1h8.5v8.5l-8.5-1.2V11.5Zm0-1V3.7L20.5 2.5V10.5H12Z" />
        </svg>
      );
    case "macos":
      return (
        <svg className="platform-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M17.2 12.6c0-2.5 2-3.7 2.1-3.8-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.8-3.2-.8-1.6 0-3.2.9-4 2.4-1.7 3-.4 7.4 1.2 9.8.8 1.2 1.8 2.5 3 2.5 1.2 0 1.7-.8 3.2-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8-.1 0-2.6-1-2.6-3.9zM14.7 5.3c.7-.8 1.1-1.9 1-3.1-.9 0-2.1.6-2.8 1.4-.6.7-1.1 1.9-1 3 1 .1 2-.5 2.8-1.3z" />
        </svg>
      );
    case "android":
      return (
        <svg className="platform-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M5.4 9.3a1.1 1.1 0 0 0-1.1 1.1v5.7a1.1 1.1 0 1 0 2.2 0v-5.7a1.1 1.1 0 0 0-1.1-1.1Zm13.2 0a1.1 1.1 0 0 0-1.1 1.1v5.7a1.1 1.1 0 1 0 2.2 0v-5.7a1.1 1.1 0 0 0-1.1-1.1ZM7.4 17.8c0 .6.5 1 1.1 1h.8v2.2a1.1 1.1 0 1 0 2.2 0v-2.2h1.6v2.2a1.1 1.1 0 1 0 2.2 0v-2.2h.8c.6 0 1.1-.4 1.1-1V9.6H7.4v8.2ZM16 4.3l1-1.6a.4.4 0 0 0-.7-.4l-1 1.7c-.9-.4-1.9-.7-2.8-.7-1.1 0-2.1.3-3 .7l-1-1.7a.4.4 0 0 0-.7.4l1 1.6C7.2 5.2 6.4 6.6 6.4 8.3v.1h11.2v-.1c0-1.7-.8-3.1-2-3.9ZM9.6 7c-.4 0-.7-.3-.7-.6 0-.4.3-.7.7-.7s.6.3.6.7c0 .3-.3.6-.6.6Zm4.8 0c-.4 0-.7-.3-.7-.6 0-.4.3-.7.7-.7s.6.3.6.7c0 .3-.3.6-.6.6Z" />
        </svg>
      );
    case "ios":
      return (
        <svg className="platform-icon" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M8 2.5h8a3.3 3.3 0 0 1 3.3 3.3v12.4A3.3 3.3 0 0 1 16 21.5H8a3.3 3.3 0 0 1-3.3-3.3V5.8A3.3 3.3 0 0 1 8 2.5Zm0 1.6a1.7 1.7 0 0 0-1.7 1.7v12.4A1.7 1.7 0 0 0 8 19.9h8a1.7 1.7 0 0 0 1.7-1.7V5.8A1.7 1.7 0 0 0 16 4.1H8Zm2 .9h4a.5.5 0 1 1 0 1h-4a.5.5 0 1 1 0-1Zm2 12.4a.9.9 0 1 1 0 1.8.9.9 0 0 1 0-1.8Z" />
        </svg>
      );
    default:
      return null;
  }
}

type DownloadButtonProps = {
  href: string;
  filename?: string | null;
  variant?: "primary" | "secondary" | "disabled";
  icon: ReactNode;
  label: string;
  hint: string;
};

function DownloadButton({ href, filename, variant = "secondary", icon, label, hint }: DownloadButtonProps) {
  const className = `dl-button dl-button--${variant}`;
  if (variant === "disabled") {
    return (
      <span className={className} aria-disabled="true">
        <span className="dl-button__icon" aria-hidden="true">{icon}</span>
        <span className="dl-button__body">
          <span className="dl-button__label">{label}</span>
          <span className="dl-button__hint">{hint}</span>
        </span>
      </span>
    );
  }
  const isExternal = href.startsWith("http");
  return (
    <a
      className={className}
      href={href}
      download={filename ?? undefined}
      target={isExternal ? "_blank" : undefined}
      rel={isExternal ? "noreferrer" : undefined}
    >
      <span className="dl-button__icon" aria-hidden="true">{icon}</span>
      <span className="dl-button__body">
        <span className="dl-button__label">{label}</span>
        <span className="dl-button__hint">{hint}</span>
      </span>
    </a>
  );
}

const ICON_CLOUD = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M7 17.5h10a4.5 4.5 0 0 0 .8-9 6 6 0 0 0-11.7-.6 4.5 4.5 0 0 0 .9 9.6Z" />
    <path d="M12 12.5v4m0 0-2-2m2 2 2-2" />
  </svg>
);

const ICON_GITHUB = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <path d="M12 2a10 10 0 0 0-3.2 19.5c.5.1.7-.2.7-.5v-2c-2.8.6-3.4-1.2-3.4-1.2-.5-1.2-1.2-1.5-1.2-1.5-1-.6.1-.6.1-.6 1 .1 1.6 1.1 1.6 1.1.9 1.6 2.4 1.1 3 .9.1-.7.4-1.2.6-1.4-2.2-.3-4.6-1.1-4.6-5a4 4 0 0 1 1-2.7c-.1-.3-.5-1.4.1-2.9 0 0 .9-.3 2.8 1a9.6 9.6 0 0 1 5 0c2-1.3 2.8-1 2.8-1 .6 1.5.2 2.6.1 2.9a4 4 0 0 1 1 2.7c0 3.9-2.3 4.7-4.5 5 .4.3.7.9.7 1.9v2.8c0 .3.2.6.7.5A10 10 0 0 0 12 2Z" />
  </svg>
);

const ICON_APPSTORE = (
  <svg viewBox="0 0 24 24" aria-hidden="true">
    <circle cx="12" cy="12" r="10" />
    <path d="M8.5 16 12 9.5 15.5 16M9.8 13.8h4.4" />
  </svg>
);

export default function DownloadPage() {
  const { t, ready } = usePreferences();
  const mainRef = useRef<HTMLElement>(null);
  useRevealAnimations(mainRef, ready);

  const versionLabel = t.download.version.replace("{version}", APP_VERSION);

  return (
    <main ref={mainRef} className="subpage-shell download-shell" suppressHydrationWarning>
      <section className="download-inner" suppressHydrationWarning>
        <header className="download-header" data-reveal-anim suppressHydrationWarning>
          <h1 suppressHydrationWarning>{t.download.title}</h1>
          <p className="page-lede" suppressHydrationWarning>{t.download.lede}</p>
          <p className="download-version" suppressHydrationWarning>{versionLabel}</p>
        </header>

        <div className="download-grid" suppressHydrationWarning>
          {PLATFORM_ORDER.map((key, idx) => {
          const info = DOWNLOADS[key];
          const platform = t.download.platforms[key];
          const role = SERVER_PLATFORMS.includes(key)
            ? t.download.role.server
            : t.download.role.client;
          const isIos = key === "ios";
          return (
            <article
              key={key}
              className="download-card"
              data-reveal-anim
              style={{ "--reveal-delay": `${120 + idx * 90}ms` } as React.CSSProperties}
              suppressHydrationWarning
            >
              <header className="download-card__head" suppressHydrationWarning>
                <PlatformIcon platform={key} />
                <div className="download-card__title-block" suppressHydrationWarning>
                  <p className="download-card__role" suppressHydrationWarning>{role}</p>
                  <h2 className="download-card__name" suppressHydrationWarning>{platform.name}</h2>
                </div>
              </header>
              <dl className="download-card__meta" suppressHydrationWarning>
                <div suppressHydrationWarning>
                  <dt suppressHydrationWarning>Version</dt>
                  <dd suppressHydrationWarning>
                    {isIos && !info.appStoreUrl ? "—" : versionLabel}
                  </dd>
                </div>
                <div suppressHydrationWarning>
                  <dt suppressHydrationWarning>Size</dt>
                  <dd suppressHydrationWarning>{isIos ? "—" : info.size}</dd>
                </div>
                <div className="download-card__requirement" suppressHydrationWarning>
                  <dt suppressHydrationWarning>Requires</dt>
                  <dd suppressHydrationWarning>{platform.requirement}</dd>
                </div>
              </dl>

              <div className="download-card__buttons" suppressHydrationWarning>
                {isIos ? (
                  info.appStoreUrl ? (
                    <DownloadButton
                      href={info.appStoreUrl}
                      variant="primary"
                      icon={ICON_APPSTORE}
                      label={t.download.buttons.appStore}
                      hint={t.download.buttons.appStoreHint}
                    />
                  ) : (
                    <DownloadButton
                      href="#"
                      variant="disabled"
                      icon={ICON_APPSTORE}
                      label={t.download.buttons.appStorePending}
                      hint={t.download.buttons.appStorePendingHint}
                    />
                  )
                ) : (
                  <>
                    {info.cosUrl && (
                      <DownloadButton
                        href={info.cosUrl}
                        filename={info.filename}
                        variant="primary"
                        icon={ICON_CLOUD}
                        label={t.download.buttons.cos}
                        hint={t.download.buttons.cosHint}
                      />
                    )}
                    {info.githubUrl && (
                      <DownloadButton
                        href={info.githubUrl}
                        filename={info.filename}
                        variant="secondary"
                        icon={ICON_GITHUB}
                        label={t.download.buttons.github}
                        hint={t.download.buttons.githubHint}
                      />
                    )}
                  </>
                )}
              </div>
            </article>
          );
        })}
        </div>
      </section>
    </main>
  );
}
