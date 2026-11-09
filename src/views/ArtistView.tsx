import type { View } from "../types";
import { fmtLong } from "../lib/format";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { AppBar } from "../components/AppBar";
import { Cover } from "../components/Cover";
import { TrackRow } from "../components/TrackRow";
import { IconChevronLeft, IconPlay, IconShuffle } from "../components/icons";

export function ArtistView({ artist, onNavigate }: { artist: string; onNavigate: (view: View) => void }) {
  const { tracks, playsFor } = useLibrary();
  const { playQueue } = usePlayer();

  const list = tracks.filter((t) => t.artist.toLowerCase() === artist.toLowerCase());
  const total = list.reduce((sum, t) => sum + t.duration, 0);
  const streams = list.reduce((sum, t) => sum + playsFor(t), 0);
  const cover = list[0]?.cover ?? { from: "#1b1424", to: "#8b5cf6", accent: "#f472b6", glyph: "?" };
  const albums = [...new Set(list.map((t) => t.album))];

  return (
    <div>
      <AppBar
        title="Artist"
        eyebrow={`${list.length} track${list.length === 1 ? "" : "s"}`}
        actions={
          <button className="iconbtn iconbtn--sm" onClick={() => onNavigate({ name: "search" })} aria-label="Back">
            <IconChevronLeft width={16} height={16} />
          </button>
        }
      />

      <div className="phero">
        <div className="phero__art phero__art--round">
          <Cover cover={cover} seed={artist} round />
        </div>
        <div className="phero__body">
          <h1>{artist}</h1>
          <div className="phero__sub">
            {fmtLong(total)} · {streams.toLocaleString()} plays
          </div>
          <div className="phero__desc">{albums.join(" · ")}</div>
        </div>
      </div>

      <div className="phero__actions" style={{ marginTop: 0, marginBottom: 18 }}>
        <button className="btn btn--primary" onClick={() => playQueue(list, 0, artist)}>
          <IconPlay width={14} height={14} /> Play
        </button>
        <button className="btn" onClick={() => playQueue([...list].sort(() => Math.random() - 0.5), 0, artist)}>
          <IconShuffle width={14} height={14} /> Shuffle
        </button>
      </div>

      {[...list]
        .sort((a, b) => playsFor(b) - playsFor(a))
        .map((track) => (
          <TrackRow key={track.id} track={track} list={list} label={artist} />
        ))}
    </div>
  );
}
