"use client";

import Image from "next/image";

import { usePreferences } from "@/components/AppPreferences";
import { ISSUES_URL, PROFILE_URL, REPOSITORY_URL } from "@/lib/i18n";

export default function AboutPage() {
  const { t } = usePreferences();

  return (
    <main className="subpage-shell about-shell" suppressHydrationWarning>
      <section className="about-hero" suppressHydrationWarning>
        <div className="about-hero__copy" suppressHydrationWarning>
          <h1 suppressHydrationWarning>{t.about.title}</h1>
          <p className="page-lede" suppressHydrationWarning>
            {t.about.intro}
          </p>
          {t.about.story.map((paragraph) => (
            <p key={paragraph} suppressHydrationWarning>
              {paragraph}
            </p>
          ))}
        </div>

        <aside className="author-card" aria-label={t.about.authorTitle} suppressHydrationWarning>
          <div className="author-card__art" suppressHydrationWarning>
            <Image
              src="/brand/linloir.png"
              alt="Linloir GitHub avatar"
              width={132}
              height={132}
              className="author-card__avatar"
              priority
            />
          </div>
          <h2 suppressHydrationWarning>{t.about.authorName}</h2>
          <p className="author-card__role" suppressHydrationWarning>
            {t.about.authorRole}
          </p>
          <p suppressHydrationWarning>{t.about.authorCopy}</p>
          <p className="author-card__contact" suppressHydrationWarning>
            {t.about.contactsCopy}
          </p>
          <div className="link-row" suppressHydrationWarning>
            <a href={PROFILE_URL} target="_blank" rel="noreferrer" suppressHydrationWarning>
              {t.common.profile}
            </a>
            <a href={REPOSITORY_URL} target="_blank" rel="noreferrer" suppressHydrationWarning>
              {t.common.repository}
            </a>
            <a href={ISSUES_URL} target="_blank" rel="noreferrer" suppressHydrationWarning>
              {t.common.githubIssues}
            </a>
          </div>
        </aside>
      </section>
    </main>
  );
}
