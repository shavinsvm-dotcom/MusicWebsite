import { cx } from "../lib/cx";
import { useTheme, type Theme } from "../state/theme";
import { IconMoon, IconSun } from "./icons";

const OPTIONS: { value: Theme; label: string; icon: JSX.Element }[] = [
  { value: "dark", label: "Dark", icon: <IconMoon /> },
  { value: "light", label: "Light", icon: <IconSun /> },
];

/** Two glass pills that switch the room's light. */
export function ThemeSwitch() {
  const { theme, setTheme } = useTheme();

  return (
    <div className="theme-switch" role="group" aria-label="Appearance">
      {OPTIONS.map((option) => (
        <button
          key={option.value}
          data-on={theme === option.value}
          aria-pressed={theme === option.value}
          className={cx(theme === option.value && "is-on")}
          onClick={() => setTheme(option.value)}
        >
          {option.icon}
          {option.label}
        </button>
      ))}
    </div>
  );
}
