"use client";

import { usePreferences } from "@/components/AppPreferences";
import { ISSUES_URL } from "@/lib/i18n";

export default function PrivacyPage() {
  const { t } = usePreferences();

  return (
    <main className="subpage-shell privacy-shell" suppressHydrationWarning>
      <article className="privacy-document" suppressHydrationWarning>
        <header className="privacy-document__header" suppressHydrationWarning>
          <h1 suppressHydrationWarning>{t.privacy.title}</h1>
          <p className="privacy-effective" suppressHydrationWarning>
            {t.privacy.effective}
          </p>
          <p className="page-lede" suppressHydrationWarning>
            {t.privacy.intro}
          </p>
        </header>

        <div className="privacy-sections" suppressHydrationWarning>
          {t.privacy.sections.map((section) => (
            <section className="privacy-section" key={section.title} suppressHydrationWarning>
              <h2 suppressHydrationWarning>{section.title}</h2>
              {section.body.map((paragraph) => (
                <p key={paragraph} suppressHydrationWarning>
                  {paragraph}
                </p>
              ))}
            </section>
          ))}
        </div>

        <footer className="privacy-footer" suppressHydrationWarning>
          <a
            className="secondary-button"
            href={ISSUES_URL}
            target="_blank"
            rel="noreferrer"
            suppressHydrationWarning
          >
            {t.common.githubIssues}
          </a>
        </footer>
      </article>
    </main>
  );
}
