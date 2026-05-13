"use client";

import { usePreferences } from "@/components/AppPreferences";
import { RELEASES_URL } from "@/lib/i18n";

export default function HomePage() {
  const { t } = usePreferences();

  return (
    <main className="home-shell" aria-labelledby="hero-title" suppressHydrationWarning>
      <section className="hero" aria-label="CouchMC introduction" suppressHydrationWarning>
        <div className="hero__content" suppressHydrationWarning>
          <h1 id="hero-title" className="hero__title" suppressHydrationWarning>
            <span>{t.home.titleGreen}</span>
            {t.home.titleWhite}
          </h1>
          <p className="hero__copy" suppressHydrationWarning>
            {t.home.copy}
          </p>
          <a
            id="download"
            className="download-button"
            href={RELEASES_URL}
            target="_blank"
            rel="noreferrer"
            suppressHydrationWarning
          >
            <span>{t.common.downloadNow}</span>
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path d="M5 12h14m-6-6 6 6-6 6" />
            </svg>
          </a>
        </div>
      </section>
    </main>
  );
}
