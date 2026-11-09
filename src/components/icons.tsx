import type { SVGProps } from "react";

type P = SVGProps<SVGSVGElement>;

/**
 * Icon language: liquid glass (iOS 26 reference).
 *
 * Solid, high-contrast glyphs that sit inside rounded-square glass tiles; strokes
 * are heavy (2.2–2.7) with round caps so they stay legible at 18 px. Filled shapes
 * are preferred over thin outlines — that's what gives the tiles their weight.
 */
const base = (props: P) => ({
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2.2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  width: 20,
  height: 20,
  ...props,
});

const solid = (props: P) => ({
  ...base(props),
  fill: "currentColor",
  stroke: "none",
});

export const IconPlay = (p: P) => (
  <svg {...solid(p)}>
    <path d="M8.6 5.3c0-1 1.1-1.6 2-1.1l8.2 5.5c.8.6.8 1.8 0 2.4l-8.2 5.5c-.9.6-2-.1-2-1.1z" />
  </svg>
);

export const IconPause = (p: P) => (
  <svg {...solid(p)}>
    <rect x="6.4" y="4.4" width="4.2" height="15.2" rx="1.7" />
    <rect x="13.4" y="4.4" width="4.2" height="15.2" rx="1.7" />
  </svg>
);

export const IconPrev = (p: P) => (
  <svg {...solid(p)}>
    <path d="M18.6 5.7c0-.9-1-1.4-1.7-.9l-7.6 5.4c-.6.4-.6 1.3 0 1.7l7.6 5.4c.7.5 1.7 0 1.7-.9z" />
    <rect x="4.4" y="4.8" width="2.4" height="14.4" rx="1.2" />
  </svg>
);

export const IconNext = (p: P) => (
  <svg {...solid(p)}>
    <path d="M5.4 5.7c0-.9 1-1.4 1.7-.9l7.6 5.4c.6.4.6 1.3 0 1.7L7.1 17.3c-.7.5-1.7 0-1.7-.9z" />
    <rect x="17.2" y="4.8" width="2.4" height="14.4" rx="1.2" />
  </svg>
);

export const IconSearch = (p: P) => (
  <svg {...base(p)} strokeWidth={2.5}>
    <circle cx="11" cy="11" r="6.1" />
    <path d="m16.1 16.1 4 4" />
  </svg>
);

export const IconCompass = (p: P) => (
  <svg {...solid(p)}>
    <path
      fillRule="evenodd"
      d="M12 2.6a9.4 9.4 0 1 0 0 18.8 9.4 9.4 0 0 0 0-18.8zm0 2.1a7.3 7.3 0 1 1 0 14.6 7.3 7.3 0 0 1 0-14.6z"
    />
    <path d="m16 8-2.3 5.5-5.7 2.6 2.3-5.5z" />
  </svg>
);

export const IconLibrary = (p: P) => (
  <svg {...solid(p)}>
    <rect x="3.6" y="4.4" width="2.7" height="15.2" rx="1.35" />
    <rect x="8.2" y="4.4" width="2.7" height="15.2" rx="1.35" />
    <rect x="12.8" y="4.4" width="7.6" height="15.2" rx="2.4" />
  </svg>
);

export const IconUser = (p: P) => (
  <svg {...solid(p)}>
    <circle cx="12" cy="8.1" r="4" />
    <path d="M12 13.4c-4.2 0-7.3 2.3-7.8 6.3-.1.7.5 1.3 1.2 1.3h13.2c.7 0 1.3-.6 1.2-1.3-.5-4-3.6-6.3-7.8-6.3z" />
  </svg>
);

export const IconGear = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M3.6 7.8h16.8M3.6 16.2h16.8" />
    <circle cx="9.2" cy="7.8" r="2.7" fill="currentColor" stroke="none" />
    <circle cx="15" cy="16.2" r="2.7" fill="currentColor" stroke="none" />
  </svg>
);

export const IconMore = (p: P) => (
  <svg {...solid(p)}>
    <circle cx="5.3" cy="12" r="1.9" />
    <circle cx="12" cy="12" r="1.9" />
    <circle cx="18.7" cy="12" r="1.9" />
  </svg>
);

export const IconHeart = ({ filled, ...p }: P & { filled?: boolean }) => (
  <svg {...base(p)} fill={filled ? "currentColor" : "none"} strokeWidth={filled ? 0 : 2.2}>
    <path d="M12 20.4c-.4 0-.8-.2-1.1-.4C7.1 17.1 3.6 14 3.6 10.2 3.6 7.3 5.8 5 8.6 5c1.4 0 2.6.7 3.4 1.7A4.3 4.3 0 0 1 15.4 5c2.8 0 5 2.3 5 5.2 0 3.8-3.5 6.9-7.3 9.8-.3.2-.7.4-1.1.4z" />
  </svg>
);

export const IconVolume = (p: P) => (
  <svg {...base(p)}>
    <path d="M11.4 4.5 6.8 8.3H3.4v7.4h3.4l4.6 3.8z" fill="currentColor" stroke="none" />
    <path d="M15.2 9.1a4 4 0 0 1 0 5.8M18 6.3a7.9 7.9 0 0 1 0 11.4" />
  </svg>
);

export const IconMute = (p: P) => (
  <svg {...base(p)}>
    <path d="M11.4 4.5 6.8 8.3H3.4v7.4h3.4l4.6 3.8z" fill="currentColor" stroke="none" />
    <path d="m15.6 9.6 4.4 4.8M20 9.6l-4.4 4.8" />
  </svg>
);

export const IconShuffle = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M16.4 4.4h4v4" />
    <path d="M20.4 4.4 4 20.4" />
    <path d="M16.4 19.6h4v-4" />
    <path d="M4 4.4 8.9 9" />
    <path d="m14.9 14.9 5.5 4.7" />
  </svg>
);

export const IconRepeat = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M16.6 3.6 20 6.6l-3.4 3" />
    <path d="M20 6.6H8.4A4.4 4.4 0 0 0 4 11v1.2" />
    <path d="M7.4 20.4 4 17.4l3.4-3" />
    <path d="M4 17.4h11.6A4.4 4.4 0 0 0 20 13v-1.2" />
  </svg>
);

export const IconRepeatOne = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M16.6 3.6 20 6.6l-3.4 3" />
    <path d="M20 6.6H8.4A4.4 4.4 0 0 0 4 11v1.2" />
    <path d="M7.4 20.4 4 17.4l3.4-3" />
    <path d="M4 17.4h11.6A4.4 4.4 0 0 0 20 13v-1.2" />
    <path d="M11 10.6h1.4v3.6" />
  </svg>
);

export const IconUpload = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M12 15.6V4.2m0 0L7.6 8.6M12 4.2l4.4 4.4" />
    <path d="M4.6 14.6v3.2a2.4 2.4 0 0 0 2.4 2.4h10a2.4 2.4 0 0 0 2.4-2.4v-3.2" />
  </svg>
);

export const IconPlus = (p: P) => (
  <svg {...base(p)} strokeWidth={2.6}>
    <path d="M12 4.8v14.4M4.8 12h14.4" />
  </svg>
);

export const IconX = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M6 6l12 12M18 6 6 18" />
  </svg>
);

export const IconChevronDown = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="m5.6 9.2 6.4 6.4 6.4-6.4" />
  </svg>
);

export const IconChevronLeft = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M14.8 5.6 8.4 12l6.4 6.4" />
  </svg>
);

export const IconArrowRight = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M4.4 12h15.2m0 0-5.6-5.6M19.6 12l-5.6 5.6" />
  </svg>
);

export const IconQueue = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M4 7.2h9.4M4 12h9.4M4 16.8h5.6" />
    <path d="M18.4 8.4v8.2a2.3 2.3 0 1 1-2.3-2.3" />
  </svg>
);

export const IconLyrics = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <rect x="3.6" y="3.6" width="16.8" height="16.8" rx="4.4" />
    <path d="M8 8.6h8M8 12h8M8 15.4h4.4" />
  </svg>
);

export const IconTrash = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M4.4 7h15.2M9.4 7V4.6h5.2V7" />
    <path d="M6.4 7l.8 12.1a2 2 0 0 0 2 1.9h5.6a2 2 0 0 0 2-1.9L17.6 7" />
  </svg>
);

export const IconDownload = (p: P) => (
  <svg {...base(p)} strokeWidth={2.4}>
    <path d="M12 4.2v11.4m0 0 4.4-4.4M12 15.6 7.6 11.2" />
    <path d="M4.6 19.4h14.8" />
  </svg>
);

export const IconWave = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M3.2 12h2.2l1.7-5.2 2 11 2.1-14 2 17 2-9 1.8 5.2h3.8" />
  </svg>
);

export const IconHeadphones = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M4 14.2v-1.6a8 8 0 0 1 16 0v1.6" />
    <rect x="2.6" y="13" width="4.6" height="7.4" rx="2.3" fill="currentColor" stroke="none" />
    <rect x="16.8" y="13" width="4.6" height="7.4" rx="2.3" fill="currentColor" stroke="none" />
  </svg>
);

export const IconSparkle = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M12 3.2 13.7 9l5.8 1.7-5.8 1.7L12 18.2l-1.7-5.8L4.5 10.7 10.3 9z" />
  </svg>
);

export const IconCheck = (p: P) => (
  <svg {...base(p)} strokeWidth={2.6}>
    <path d="m5 12.4 4.6 4.6L19 7" />
  </svg>
);

export const IconFolder = (p: P) => (
  <svg {...base(p)} strokeWidth={2.2}>
    <path d="M3.4 7.6a2.2 2.2 0 0 1 2.2-2.2h3.2l1.9 2.3h7.7a2.2 2.2 0 0 1 2.2 2.2v6.9a2.2 2.2 0 0 1-2.2 2.2H5.6a2.2 2.2 0 0 1-2.2-2.2z" />
  </svg>
);

export const IconPin = (p: P) => (
  <svg {...solid(p)}>
    <path d="M12 2.8a6.4 6.4 0 0 0-6.4 6.4c0 4.6 5.5 10.8 5.7 11a.9.9 0 0 0 1.4 0c.2-.2 5.7-6.4 5.7-11A6.4 6.4 0 0 0 12 2.8zm0 8.9a2.6 2.6 0 1 1 0-5.2 2.6 2.6 0 0 1 0 5.2z" />
  </svg>
);

export const IconClock = (p: P) => (
  <svg {...base(p)} strokeWidth={2.3}>
    <circle cx="12" cy="12" r="8.6" />
    <path d="M12 7.2V12l3.4 2.2" />
  </svg>
);

export const IconSun = (p: P) => (
  <svg {...base(p)} strokeWidth={2}>
    <circle cx="12" cy="12" r="4.2" />
    <path d="M12 3.4v2.1M12 18.5v2.1M3.4 12h2.1M18.5 12h2.1M6 6l1.5 1.5M16.5 16.5 18 18M18 6l-1.5 1.5M7.5 16.5 6 18" />
  </svg>
);

export const IconMoon = (p: P) => (
  <svg {...base(p)} strokeWidth={2}>
    <path d="M20 14.4A8.4 8.4 0 0 1 9.6 4a8.6 8.6 0 1 0 10.4 10.4z" />
  </svg>
);
