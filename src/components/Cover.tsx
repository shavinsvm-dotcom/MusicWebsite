import { useMemo } from "react";
import type { Cover as CoverType } from "../types";
import { photoArt } from "../lib/art";
import { cx } from "../lib/cx";

/** Artwork surface — real artwork when the track has it, generated photo art otherwise. */
export function Cover({
  cover,
  seed,
  className,
  round,
  art,
}: {
  cover: CoverType;
  seed?: string;
  className?: string;
  round?: boolean;
  /** Embedded or looked-up artwork (data URL or http URL). */
  art?: string;
}) {
  const generated = useMemo(
    () => (art ? "" : photoArt(cover, seed ?? cover.glyph)),
    [cover, seed, art],
  );

  if (art) {
    return (
      <div className={cx("cover", round && "cover--round", className)} aria-hidden="true">
        <img
          src={art}
          alt=""
          loading="lazy"
          style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
        />
      </div>
    );
  }

  return (
    <div
      className={cx("cover", round && "cover--round", className)}
      style={{ backgroundImage: `url("${generated}")` }}
      aria-hidden="true"
    />
  );
}
