import type { TabName, View } from "../types";
import { cx } from "../lib/cx";

/**
 * Bottom navigation, five equal tabs with small labels. Active tab is white,
 * the rest sit back at low opacity so the artwork stays the loudest thing.
 */

const stroke = {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.7,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

const IconDiscover = () => (
  <svg {...stroke}>
    <circle cx="12" cy="12" r="9" />
    <path d="m15.6 8.4-2.1 5.1-5.1 2.1 2.1-5.1z" />
  </svg>
);

const IconSearch = () => (
  <svg {...stroke}>
    <circle cx="10.8" cy="10.8" r="6.4" />
    <path d="m15.6 15.6 4.2 4.2" />
  </svg>
);

const IconUpload = () => (
  <svg {...stroke}>
    <path d="M12 16.2V4.8m0 0L7.8 9M12 4.8 16.2 9" />
    <path d="M4.8 17.4v1a1.8 1.8 0 0 0 1.8 1.8h10.8a1.8 1.8 0 0 0 1.8-1.8v-1" />
  </svg>
);

const IconLibrary = () => (
  <svg {...stroke}>
    <path d="M5 5.4v13.2M9.4 4.2v15.6M13.8 6v12" />
    <rect x="17" y="7.6" width="3" height="8.8" rx="1.2" />
  </svg>
);

const IconProfile = () => (
  <svg {...stroke}>
    <circle cx="12" cy="8.2" r="3.7" />
    <path d="M4.9 19.6c.7-3.6 3.6-5.6 7.1-5.6s6.4 2 7.1 5.6" />
  </svg>
);

export function TabBar({
  active,
  onNavigate,
  onUpload,
}: {
  active: TabName;
  onNavigate: (view: View) => void;
  onUpload: () => void;
}) {
  // Detail screens inherit their opener's tab, so `active` is the only signal.
  const is = (name: TabName) => active === name;

  const tabs: { label: string; on: boolean; go: () => void; icon: JSX.Element }[] = [
    { label: "Discover", on: is("discover"), go: () => onNavigate({ name: "discover" }), icon: <IconDiscover /> },
    {
      label: "Search",
      on: is("search"),
      go: () => onNavigate({ name: "search" }),
      icon: <IconSearch />,
    },
    { label: "Upload", on: is("upload"), go: onUpload, icon: <IconUpload /> },
    { label: "Library", on: is("library"), go: () => onNavigate({ name: "library" }), icon: <IconLibrary /> },
    { label: "You", on: is("you"), go: () => onNavigate({ name: "you" }), icon: <IconProfile /> },
  ];

  return (
    <nav className="tabbar" aria-label="Primary">
      {tabs.map((tab) => (
        <button
          key={tab.label}
          className={cx("tab", tab.on && "tab--on")}
          onClick={tab.go}
          aria-label={tab.label}
          aria-current={tab.on ? "page" : undefined}
        >
          {tab.icon}
          <span className="tab__label">{tab.label}</span>
        </button>
      ))}
    </nav>
  );
}
