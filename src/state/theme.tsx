import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";

export type Theme = "dark" | "light";

const LS_KEY = "nocturne.theme";
const META: Record<Theme, string> = { dark: "#07060d", light: "#f3f0f7" };

const ThemeCtx = createContext<{ theme: Theme; setTheme: (theme: Theme) => void } | null>(null);

function readTheme(): Theme {
  try {
    const saved = localStorage.getItem(LS_KEY);
    if (saved === "dark" || saved === "light") return saved;
  } catch {
    /* storage blocked — fall through to the system preference */
  }
  return window.matchMedia?.("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

/** Applies the theme to <html data-theme> so CSS owns every colour. */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(readTheme);

  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem(LS_KEY, theme);
    } catch {
      /* not fatal */
    }
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", META[theme]);
  }, [theme]);

  const setTheme = useCallback((next: Theme) => setThemeState(next), []);

  return <ThemeCtx.Provider value={{ theme, setTheme }}>{children}</ThemeCtx.Provider>;
}

export function useTheme() {
  const ctx = useContext(ThemeCtx);
  if (!ctx) throw new Error("useTheme must be used inside ThemeProvider");
  return ctx;
}
