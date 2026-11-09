import type { Track } from "../types";
import { fmtTime } from "../lib/format";
import { cx } from "../lib/cx";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { Cover } from "./Cover";
import { IconHeart, IconPlay, IconTrash } from "./icons";

export function TrackRow({
  track,
  list,
  label,
  onDelete,
}: {
  track: Track;
  list: Track[];
  label: string;
  onDelete?: (track: Track) => void;
}) {
  const { current, isPlaying, playTrack, togglePlay } = usePlayer();
  const { isLiked, toggleLike } = useLibrary();
  const active = current?.id === track.id;
  const playing = active && isPlaying;

  const open = () => (active ? togglePlay() : playTrack(track, list, label));

  return (
    <div
      className={cx("lrow", active && "lrow--active")}
      role="button"
      tabIndex={0}
      onClick={open}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          open();
        }
      }}
    >
      <span className="lrow__art">
        <Cover cover={track.cover} seed={track.id} art={track.art} />
      </span>
      <span className="lrow__meta">
        <span className="lrow__t">{track.title}</span>
        <span className="lrow__s">{track.artist}</span>
      </span>
      <span className="lrow__time">{fmtTime(track.duration)}</span>
      <button
        className={cx("lrow__like", isLiked(track.id) && "lrow__like--on")}
        aria-label={isLiked(track.id) ? "Unlike" : "Like"}
        onClick={(e) => {
          e.stopPropagation();
          toggleLike(track.id);
        }}
      >
        <IconHeart filled={isLiked(track.id)} />
      </button>
      <span className="lrow__go">
        {playing ? (
          <span className="eq" aria-label="Playing">
            <span />
            <span />
            <span />
          </span>
        ) : onDelete ? (
          <button
            aria-label={`Delete ${track.title}`}
            style={{ display: "grid", placeItems: "center", color: "inherit" }}
            onClick={(e) => {
              e.stopPropagation();
              onDelete(track);
            }}
          >
            <IconTrash width={14} height={14} />
          </button>
        ) : (
          <IconPlay />
        )}
      </span>
    </div>
  );
}
