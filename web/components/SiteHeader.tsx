"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";

import { usePreferences } from "@/components/AppPreferences";
import { RELEASES_URL, REPOSITORY_URL } from "@/lib/i18n";

const navItems = [
  { href: "/", key: "home" },
  { href: RELEASES_URL, key: "download", external: true },
  { href: REPOSITORY_URL, key: "github", external: true },
  { href: "/about", key: "about" },
  { href: "/privacy", key: "privacy" },
] as const;

export function SiteHeader() {
  const pathname = usePathname();
  const { t, theme, resolvedTheme, cycleTheme, toggleLanguage } = usePreferences();
  const headerRef = useRef<HTMLElement>(null);
  const glassRef = useRef<HTMLDivElement>(null);
  const [entered, setEntered] = useState(false);

  useEffect(() => {
    const handle = window.setTimeout(() => {
      setEntered(true);
    }, 0);
    return () => window.clearTimeout(handle);
  }, []);

  useEffect(() => {
    let frame = 0;

    const updateHeaderProgress = () => {
      frame = 0;
      const progress = Math.min(window.scrollY / 120, 1);
      const header = headerRef.current;
      const glass = glassRef.current;
      if (!header || !glass) {
        return;
      }

      const color = resolvedTheme === "light" ? "245, 242, 233" : "5, 5, 4";
      const topAlpha = progress * (resolvedTheme === "light" ? 0.72 : 0.56);
      const bottomAlpha = progress * (resolvedTheme === "light" ? 0.5 : 0.34);
      const tailAlpha = progress * (resolvedTheme === "light" ? 0.62 : 0.44);
      const borderAlpha = progress * (resolvedTheme === "light" ? 0.12 : 0.08);

      glass.style.setProperty("--header-progress", progress.toFixed(3));
      glass.style.setProperty("--header-bg-top", `rgba(${color}, ${topAlpha.toFixed(3)})`);
      glass.style.setProperty("--header-bg-bottom", `rgba(${color}, ${bottomAlpha.toFixed(3)})`);
      glass.style.setProperty("--header-tail-start", `rgba(${color}, ${tailAlpha.toFixed(3)})`);
      glass.style.setProperty("--header-border", `rgba(${color}, ${borderAlpha.toFixed(3)})`);
      glass.style.setProperty("--header-blur", `${(progress * 28).toFixed(2)}px`);
      glass.style.setProperty("--header-height", `${header.offsetHeight}px`);
    };

    const onScroll = () => {
      if (frame === 0) {
        frame = window.requestAnimationFrame(updateHeaderProgress);
      }
    };

    updateHeaderProgress();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", updateHeaderProgress);
    const resizeObserver = new ResizeObserver(updateHeaderProgress);
    if (headerRef.current) {
      resizeObserver.observe(headerRef.current);
    }

    return () => {
      if (frame !== 0) {
        window.cancelAnimationFrame(frame);
      }
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", updateHeaderProgress);
      resizeObserver.disconnect();
    };
  }, [resolvedTheme]);

  return (
    <>
      <div
        ref={glassRef}
        className={`site-header-glass${entered ? " site-header-glass--enter" : ""}`}
        aria-hidden="true"
      />
      <header
        ref={headerRef}
        className={[
          "site-header",
          pathname === "/" ? "site-header--home" : "",
          entered ? "site-header--enter" : "",
        ]
          .filter(Boolean)
          .join(" ")}
        aria-label="Primary navigation"
        suppressHydrationWarning
      >
        <Link className="brand" href="/" aria-label="CouchMC home" suppressHydrationWarning>
          <Image
            className="brand-mark"
            src="/brand/grass-block-128.png"
            alt=""
            width={42}
            height={42}
            priority
          />
          <span>{t.common.brand}</span>
        </Link>

        <div className="header-right" suppressHydrationWarning>
          <nav className="site-nav" aria-label="Main navigation" suppressHydrationWarning>
            {navItems.map((item) => {
              const active =
                !("external" in item) &&
                (item.href === "/" ? pathname === "/" : pathname.startsWith(item.href));
              const label = t.common.nav[item.key];
              if ("external" in item) {
                return (
                  <a
                    key={item.key}
                    className="site-nav__link"
                    href={item.href}
                    target="_blank"
                    rel="noreferrer"
                    suppressHydrationWarning
                  >
                    {label}
                  </a>
                );
              }
              return (
                <Link
                  key={item.key}
                  className={`site-nav__link${active ? " site-nav__link--active" : ""}`}
                  href={item.href}
                  suppressHydrationWarning
                >
                  {label}
                </Link>
              );
            })}
          </nav>

          <div className="preference-controls" aria-label="Display preferences" suppressHydrationWarning>
            <button
              className="preference-button"
              type="button"
              onClick={cycleTheme}
              suppressHydrationWarning
            >
              <span
                className="preference-button__icon preference-button__icon--theme"
                aria-hidden="true"
              >
                {theme === "dark" ? "☾" : theme === "light" ? "☼" : "◐"}
              </span>
              <span className="preference-button__text">{t.common.theme[theme]}</span>
            </button>
            <button
              className="preference-button"
              type="button"
              onClick={toggleLanguage}
              suppressHydrationWarning
            >
              <span
                className="preference-button__icon preference-button__icon--language"
                aria-hidden="true"
              >
                文
              </span>
              <span className="preference-button__text">{t.common.language.value}</span>
            </button>
          </div>
        </div>
      </header>
    </>
  );
}
