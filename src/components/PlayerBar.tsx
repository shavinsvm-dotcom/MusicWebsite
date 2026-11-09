import { cx } from "../lib/cx";
import { usePlayer } from "../state/player";
import { Cover } from "./Cover";
import { IconNext, IconPause, IconPlay } from "./icons";

/**
 * Mini player: the artwork becomes a vinyl disc with a neon progress ring,
 * so the row reads as one object instead of a bar with a stray underline.
 */
export function PlayerBar() {
  const { current, isPlaying, time, duration, togglePlay, next, openFull } = usePlayer();
  if (!current) return null;

  const total = duration || current.duration || 0;
  const pct = total > 0 ? Math.min(100, (time / total) * 100) : 0;

  return (
    <div className="minibar">
      <button
        type="button"
        className={cx("minibar__disc", isPlaying && "is-spin")}
        style={{ "--p": pct } as React.CSSProperties}
        onClick={openFull}
        aria-label="Open player"
      >
        <span className="minibar__discart">
          <Cover cover={current.cover} seed={current.id} art={current.art} />
        </span>
      </button>
      <button type="button" className="minibar__meta" onClick={openFull} aria-label="Open player">
        <div className="minibar__t">{current.title}</div>
        <div className="minibar__a">{current.artist}</div>
      </button>
      <button
        className="minibar__btn"
        onClick={(e) => {
          e.stopPropagation();
          togglePlay();
        }}
        aria-label={isPlaying ? "Pause" : "Play"}
      >
        {isPlaying ? <IconPause /> : <IconPlay />}
      </button>
      <button
        className="minibar__btn"
        onClick={(e) => {
          e.stopPropagation();
          next();
        }}
        aria-label="Next"
      >
        <IconNext />
      </button>
    </div>
  );
}
