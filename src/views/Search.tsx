import { useEffect, useMemo, useRef, useState } from "react";
import type { View } from "../types";
import { fmtPlays } from "../lib/format";
import { cx } from "../lib/cx";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { AppBar } from "../components/AppBar";
import { Cover } from "../components/Cover";
import { PlaylistCard } from "../components/PlaylistCard";
import { TrackRow } from "../components/TrackRow";
import { IconSearch } from "../components/icons";

type Filter = "songs" | "artists" | "playlists";

export function Search({
  query,
  setQuery,
  onNavigate,
}: {
  query: string;
  setQuery: (value: string) => void;
  onNavigate: (view: View) => void;
}) {
  const { tracks, playlists, playsFor } = useLibrary();
  const { playQueue } = usePlayer();
  const [filter, setFilter] = useState<Filter>("songs");
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const timer = window.setTimeout(() => inputRef.current?.focus(), 220);
    return () => window.clearTimeout(timer);
  }, []);

  const q = query.trim().toLowerCase();

  const songs = useMemo(
    () => (q ? tracks.filter((t) => [t.title, t.artist, t.album, t.genre].join(" ").toLowerCase().includes(q)) : tracks),
    [q, tracks],
  );

  const artists = useMemo(() => {
    const map = new Map<string, { name: string; count: number; cover: (typeof tracks)[number]["cover"]; plays: number }>();
    for (const track of tracks) {
      const entry = map.get(track.artist);
      if (entry) {
        entry.count += 1;
        entry.plays += playsFor(track);
      } else {
        map.set(track.artist, { name: track.artist, count: 1, cover: track.cover, plays: playsFor(track) });
      }
    }
    const all = [...map.values()].sort((a, b) => b.plays - a.plays);
    return q ? all.filter((a) => a.name.toLowerCase().includes(q)) : all;
  }, [tracks, q, playsFor]);

  const matchingPlaylists = useMemo(
    () =>
      q
        ? playlists.filter((p) => p.name.toLowerCase().includes(q))
        : playlists.filter((p) => !p.system || p.id === "sys-liked").slice(0, 4),
    [playlists, q],
  );

  return (
    <div>
      <AppBar title="Search" eyebrow="Catalogue" />

      <label className="searchbox">
        <IconSearch />
        <input
          ref={inputRef}
          value={query}
          placeholder="Tracks, artists, moods…"
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Search"
        />
        {query && (
          <button onClick={() => setQuery("")} aria-label="Clear search" style={{ color: "var(--dim)" }}>
            ✕
          </button>
        )}
      </label>

      <div className="filters">
        {(
          [
            ["songs", `Songs · ${songs.length}`],
            ["artists", `Artists · ${artists.length}`],
            ["playlists", `Playlists · ${matchingPlaylists.length}`],
          ] as [Filter, string][]
        ).map(([key, label]) => (
          <button key={key} className={cx("pill", filter === key && "pill--active")} onClick={() => setFilter(key)}>
            {label}
          </button>
        ))}
      </div>

      {filter === "artists" && (
        <div className="artistgrid">
          {artists.map((artist) => (
            <button
              key={artist.name}
              className="artist"
              onClick={() => onNavigate({ name: "artist", artist: artist.name })}
            >
              <span className="artist__disc">
                <Cover cover={artist.cover} seed={artist.name} round />
              </span>
              <span className="artist__name">{artist.name}</span>
              <span className="artist__meta">{artist.count} tracks</span>
            </button>
          ))}
          {artists.length === 0 && (
            <div className="empty" style={{ gridColumn: "1 / -1" }}>
              <h3>No artists matched</h3>
              <p>Try a shorter word.</p>
            </div>
          )}
        </div>
      )}

      {filter === "songs" && (
        <>
          <div className="section__head">
            <div>
              <h2 style={{ fontSize: 15 }}>{q ? "Results" : "Everything"}</h2>
              <div className="section__sub">{fmtPlays(songs.reduce((sum, t) => sum + playsFor(t), 0))}</div>
            </div>
            {songs.length > 0 && (
              <button className="btn btn--sm" onClick={() => playQueue(songs, 0, q ? `Search · ${query}` : "All songs")}>
                Play all
              </button>
            )}
          </div>
          {songs.map((track) => (
            <TrackRow key={track.id} track={track} list={songs} label={q ? `Search · ${query}` : "All songs"} />
          ))}
          {songs.length === 0 && (
            <div className="empty">
              <h3>Nothing matched “{query}”</h3>
              <p>Try a different word — or upload it yourself.</p>
              <button className="btn btn--primary" onClick={() => onNavigate({ name: "upload" })}>
                Upload a track
              </button>
            </div>
          )}
        </>
      )}

      {filter === "playlists" && (
        <div className="duo">
          {matchingPlaylists.map((playlist) => (
            <PlaylistCard
              key={playlist.id}
              playlist={playlist}
              onOpen={() => onNavigate({ name: "playlist", id: playlist.id })}
            />
          ))}
        </div>
      )}
    </div>
  );
}
