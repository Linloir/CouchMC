"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { flushSync } from "react-dom";

import { translations, type Language, type Translation } from "@/lib/i18n";

type DocumentWithViewTransition = Document & {
  startViewTransition?: (callback: () => void) => unknown;
};

function withViewTransition(callback: () => void) {
  if (typeof document === "undefined") {
    callback();
    return;
  }
  const docWithVT = document as DocumentWithViewTransition;
  if (typeof docWithVT.startViewTransition !== "function") {
    callback();
    return;
  }
  docWithVT.startViewTransition(() => {
    flushSync(callback);
  });
}

type ThemeChoice = "system" | "light" | "dark";
type ResolvedTheme = "light" | "dark";

type Preferences = {
  language: Language;
  setLanguage: (language: Language) => void;
  toggleLanguage: () => void;
  theme: ThemeChoice;
  resolvedTheme: ResolvedTheme;
  cycleTheme: () => void;
  t: Translation;
  // True once language + theme preferences have been restored from
  // localStorage. Components that render translatable content should gate
  // visibility / entrance animations on this so the page never paints with
  // the wrong language and then snaps to the user's preference.
  ready: boolean;
};

const PreferencesContext = createContext<Preferences | null>(null);

function getBrowserLanguage(): Language {
  if (typeof navigator === "undefined") {
    return "en";
  }
  return navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en";
}

function getStoredLanguage(): Language {
  if (typeof window === "undefined") {
    return "en";
  }
  const value = window.localStorage.getItem("couchmc-language");
  return value === "zh" || value === "en" ? value : getBrowserLanguage();
}

function getStoredTheme(): ThemeChoice {
  if (typeof window === "undefined") {
    return "system";
  }
  const value = window.localStorage.getItem("couchmc-theme");
  return value === "light" || value === "dark" || value === "system" ? value : "system";
}

function getSystemTheme(): ResolvedTheme {
  if (typeof window === "undefined") {
    return "dark";
  }
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

export function AppPreferencesProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<Language>("en");
  const [theme, setTheme] = useState<ThemeChoice>("system");
  const [systemTheme, setSystemTheme] = useState<ResolvedTheme>("dark");
  const [ready, setReady] = useState(false);
  const resolvedTheme = theme === "system" ? systemTheme : theme;

  useEffect(() => {
    const restorePreferences = window.setTimeout(() => {
      setLanguageState(getStoredLanguage());
      setTheme(getStoredTheme());
      setSystemTheme(getSystemTheme());
      setReady(true);
    }, 0);

    const media = window.matchMedia("(prefers-color-scheme: light)");
    const onChange = () => setSystemTheme(media.matches ? "light" : "dark");
    media.addEventListener("change", onChange);
    return () => {
      window.clearTimeout(restorePreferences);
      media.removeEventListener("change", onChange);
    };
  }, []);

  useEffect(() => {
    document.documentElement.dataset.theme = resolvedTheme;
    document.documentElement.dataset.themeChoice = theme;
  }, [resolvedTheme, theme]);

  useEffect(() => {
    document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
  }, [language]);

  useEffect(() => {
    if (ready) {
      document.documentElement.dataset.ready = "1";
    }
  }, [ready]);

  const setLanguage = useCallback((nextLanguage: Language) => {
    setLanguageState(nextLanguage);
    window.localStorage.setItem("couchmc-language", nextLanguage);
  }, []);

  const toggleLanguage = useCallback(() => {
    setLanguageState((currentLanguage) => {
      const nextLanguage = currentLanguage === "en" ? "zh" : "en";
      window.localStorage.setItem("couchmc-language", nextLanguage);
      return nextLanguage;
    });
  }, []);

  const cycleTheme = useCallback(() => {
    const nextTheme: ThemeChoice =
      theme === "system" ? "light" : theme === "light" ? "dark" : "system";
    withViewTransition(() => {
      setTheme(nextTheme);
    });
    window.localStorage.setItem("couchmc-theme", nextTheme);
  }, [theme]);

  const value = useMemo<Preferences>(
    () => ({
      language,
      setLanguage,
      toggleLanguage,
      theme,
      resolvedTheme,
      cycleTheme,
      t: translations[language],
      ready,
    }),
    [cycleTheme, language, ready, resolvedTheme, setLanguage, theme, toggleLanguage],
  );

  return <PreferencesContext.Provider value={value}>{children}</PreferencesContext.Provider>;
}

export function usePreferences() {
  const value = useContext(PreferencesContext);
  if (!value) {
    throw new Error("usePreferences must be used inside AppPreferencesProvider");
  }
  return value;
}
