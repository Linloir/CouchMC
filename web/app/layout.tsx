import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";

import { AppPreferencesProvider } from "@/components/AppPreferences";
import { SiteHeader } from "@/components/SiteHeader";
import { BLUR_PLACEHOLDERS } from "@/lib/blur-placeholders";
import { translations } from "@/lib/i18n";

import "./globals.css";

/* Inject CSS variables for the hero background blur placeholders. Embedded
   as a data URI in CSS so the first paint shows a tiny blurred version of
   the hero before the full-resolution image finishes decoding. */
const HERO_BG_VARS = `:root{--hero-bg-blur-dark:url("${BLUR_PLACEHOLDERS["background"]}");--hero-bg-blur-light:url("${BLUR_PLACEHOLDERS["background-light"]}");}`;

export const metadata: Metadata = {
  title: translations.en.meta.title,
  description: translations.en.meta.description,
  icons: {
    icon: "/brand/grass-block-64.png",
    apple: "/brand/grass-block-256.png",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "dark light",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f5f2e9" },
    { media: "(prefers-color-scheme: dark)", color: "#050504" },
  ],
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <style dangerouslySetInnerHTML={{ __html: HERO_BG_VARS }} />
      </head>
      <body>
        <AppPreferencesProvider>
          <SiteHeader />
          {children}
        </AppPreferencesProvider>
      </body>
    </html>
  );
}
