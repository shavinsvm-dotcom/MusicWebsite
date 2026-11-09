import type { CSSProperties } from "react";

/** CSSProperties plus custom-property support (`--c1`, `--pct`, …). */
export type CSSVars = CSSProperties & Record<`--${string}`, string | number>;
