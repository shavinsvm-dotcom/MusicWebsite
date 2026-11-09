import type { Playlist } from "../types";
import { fmtLong } from "../lib/format";
import { cx } from "../lib/cx";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { Cover } from "./Cover";
import { IconPause, IconPlay } from "./icons";

export function PlaylistCard({ playlist, onOpen }: { playlist: Playlist; onOpen: () => void }) {
  const { tracks } = useLibrary();
  const { playQueue, current, isPlaying, togglePlay } = usePlayer();

  const list = playlist.trackIds
    .map((id) => tracks.find((t) => t.id === id))
    .filter((t): t is NonNullable<typeof t> => Boolean(t));
  const total = list.reduce((sum, t) => sum + t.duration, 0);
  const active = Boolean(current && playlist.trackIds.includes(current.id)) && isPlaying;

  return (
    <div className="gcard">
      <div
        className="gcard__art"
        role="button"
        tabIndex={0}
        onClick={onOpen}
        onKeyDown={(e) => e.key === "Enter" && onOpen()}
      >
        <Cover cover={playlist.cover} seed={playlist.id} />
        <button
          className={cx("gcard__play", active && "gcard__play--on")}
          aria-label={active ? `Pause ${playlist.name}` : `Play ${playlist.name}`}
          onClick={(e) => {
            e.stopPropagation();
            if (active) togglePlay();
            else if (list.length) playQueue(list, 0, playlist.name);
          }}
        >
          {active ? <IconPause /> : <IconPlay />}
        </button>
      </div>
      <div role="button" tabIndex={0} onClick={onOpen} onKeyDown={(e) => e.key === "Enter" && onOpen()}>
        <div className="gcard__t">{playlist.name}</div>
        <div className="gcard__s">
          {list.length} tracks · {fmtLong(total)}
        </div>
      </div>
    </div>
  );
}
