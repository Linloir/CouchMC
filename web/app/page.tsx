"use client";

import Link from "next/link";
import { useEffect, useLayoutEffect, useRef, type RefObject } from "react";

import { usePreferences } from "@/components/AppPreferences";
import { BLUR_PLACEHOLDERS } from "@/lib/blur-placeholders";

/**
 * Walks the subtree under `ref`, finds every `[data-reveal-anim]` element,
 * and decides for each whether to:
 *   - leave it alone (already above the fold on a mid-page refresh — just
 *     show it, no entrance),
 *   - mark it "shown" so it plays the entrance animation now (fresh top
 *     load, in-view elements),
 *   - mark it "pending" and hide it until it scrolls into view (below the
 *     fold at mount).
 *
 * The hook is gated on `ready` so the entrance animation only starts after
 * AppPreferences has restored language + theme from localStorage. That way
 * we don't paint English content for a beat before snapping to the user's
 * preferred Chinese (or vice versa).
 */
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
      // else: above-fold on a restored-scroll load. Leave as-is (visible).
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

/**
 * Marks an <img> as loaded by flipping `data-loaded="1"` once it's decoded.
 * Handles both the live-load and the already-cached case (where the load
 * event has already fired before we attach the listener).
 */
function useImgLoaded(ref: RefObject<HTMLImageElement | null>) {
  useEffect(() => {
    const img = ref.current;
    if (!img) return;
    const mark = () => {
      img.dataset.loaded = "1";
    };
    if (img.complete && img.naturalWidth > 0) {
      mark();
      return;
    }
    img.addEventListener("load", mark, { once: true });
    return () => img.removeEventListener("load", mark);
  }, [ref]);
}

/**
 * Preloads the hero background image off the DOM and flips a global
 * `data-hero-bg-loaded` attribute on `<html>` once it's ready. The CSS
 * watches that flag and fades the sharp image in over the blurred
 * placeholder.
 */
function useHeroBackgroundReady(resolvedTheme: "light" | "dark") {
  useEffect(() => {
    if (typeof window === "undefined") return;
    document.documentElement.removeAttribute("data-hero-bg-loaded");
    const src = resolvedTheme === "light"
      ? "/assets/background-light.webp"
      : "/assets/background.webp";
    const img = new Image();
    const mark = () => {
      document.documentElement.dataset.heroBgLoaded = "1";
    };
    img.addEventListener("load", mark, { once: true });
    img.src = src;
    if (img.complete && img.naturalWidth > 0) {
      mark();
    }
    return () => img.removeEventListener("load", mark);
  }, [resolvedTheme]);
}

function FeatureMedia({
  baseName,
  alt,
  eager,
}: {
  baseName: string;
  alt: string;
  eager: boolean;
}) {
  const imgRef = useRef<HTMLImageElement>(null);
  useImgLoaded(imgRef);
  const blur = BLUR_PLACEHOLDERS[baseName];
  return (
    <div
      className="blur-up feature-card__media"
      data-reveal-anim
      style={blur ? { "--blur-src": `url("${blur}")` } as React.CSSProperties : undefined}
      suppressHydrationWarning
    >
      <picture suppressHydrationWarning>
        <source srcSet={`/assets/features/${baseName}.webp`} type="image/webp" />
        <img
          ref={imgRef}
          src={`/assets/features/${baseName}.png`}
          alt={alt}
          width={1600}
          height={900}
          loading={eager ? "eager" : "lazy"}
          decoding="async"
        />
      </picture>
    </div>
  );
}

export default function HomePage() {
  const { t, language, ready, resolvedTheme } = usePreferences();
  const mainRef = useRef<HTMLElement>(null);
  useRevealAnimations(mainRef, ready);
  useHeroBackgroundReady(resolvedTheme);

  return (
    <main
      ref={mainRef}
      className="home-shell"
      aria-labelledby="hero-title"
      suppressHydrationWarning
    >
      <section className="hero" aria-label="CouchMC introduction" suppressHydrationWarning>
        <span className="hero__bg-placeholder" aria-hidden="true" suppressHydrationWarning />
        <span className="hero__bg-full" aria-hidden="true" suppressHydrationWarning />
        <div className="hero__content" suppressHydrationWarning>
          <h1 id="hero-title" className="hero__title" suppressHydrationWarning>
            <span>{t.home.titleGreen}</span>
            {t.home.titleWhite}
          </h1>
          <p className="hero__copy" suppressHydrationWarning>
            {t.home.copy}
          </p>
          <Link
            id="download"
            className="download-button"
            href="/download"
            suppressHydrationWarning
          >
            <span>{t.common.downloadNow}</span>
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M5 12h14m-6-6 6 6-6 6" />
            </svg>
          </Link>
        </div>
        <a className="hero__scroll-cue" href="#features" aria-label="Scroll to features" suppressHydrationWarning>
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M6 9l6 6 6-6" />
          </svg>
        </a>
      </section>

      <section
        id="features"
        className="features"
        aria-label={t.home.featuresTitle}
        suppressHydrationWarning
      >
        <header className="features__header" data-reveal-anim suppressHydrationWarning>
          <h2 className="features__title" suppressHydrationWarning>
            {t.home.featuresTitle}
          </h2>
        </header>

        <ol className="feature-list" suppressHydrationWarning>
          {t.home.features.map((feature, idx) => {
            const slug = idx + 2; // disk filenames: zh_2..zh_4 / en_2..en_4
            const baseName = `${language}_${slug}`;
            return (
              <li
                // Index keys — feature.title changes between language toggles,
                // and a changing key tears down the whole <li> on every locale
                // change, wiping our reveal-state attributes set via dataset.
                className="feature-card"
                key={idx}
                suppressHydrationWarning
              >
                <div className="feature-card__text" suppressHydrationWarning>
                  <h3
                    className="feature-card__title"
                    data-reveal-anim
                    suppressHydrationWarning
                  >
                    {feature.title}
                  </h3>
                  <p
                    className="feature-card__copy"
                    data-reveal-anim
                    suppressHydrationWarning
                  >
                    {feature.copy}
                  </p>
                </div>
                <FeatureMedia baseName={baseName} alt={feature.alt} eager={idx === 0} />
              </li>
            );
          })}
        </ol>
      </section>

      <section className="home-cta" aria-labelledby="home-cta-title" suppressHydrationWarning>
        <div className="home-cta__inner" data-reveal-anim suppressHydrationWarning>
          <h2 id="home-cta-title" className="home-cta__title" suppressHydrationWarning>
            {t.home.cta.title}
          </h2>
          <p className="home-cta__copy" suppressHydrationWarning>
            {t.home.cta.copy}
          </p>
          <Link className="download-button home-cta__button" href="/download" suppressHydrationWarning>
            <span>{t.home.cta.button}</span>
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M5 12h14m-6-6 6 6-6 6" />
            </svg>
          </Link>
        </div>
      </section>
    </main>
  );
}
