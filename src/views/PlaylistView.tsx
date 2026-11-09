import type { View } from "../types";
import { fmtLong } from "../lib/format";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { AppBar } from "../components/AppBar";
import { Cover } from "../components/Cover";
import { TrackRow } from "../components/TrackRow";
import { IconChevronLeft, IconPlay, IconShuffle, IconTrash, IconX } from "../components/icons";

export function PlaylistView({ id, onNavigate }: { id: string; onNavigate: (view: View) => void }) {
  const { playlistById, tracks, removeFromPlaylist, deletePlaylist } = useLibrary();
  const { playQueue } = usePlayer();
  const playlist = playlistById(id);

  if (!playlist) {
    return (
      <div>
        <AppBar title="Playlist" actions={<button className="iconbtn iconbtn--sm" onClick={() => onNavigate({ name: "library" })} aria-label="Back"><IconChevronLeft width={16} height={16} /></button>} />
        <div className="empty">
          <h3>Playlist not found</h3>
          <p>It may have been deleted.</p>
          <button className="btn" onClick={() => onNavigate({ name: "library" })}>
            Back to library
          </button>
        </div>
      </div>
    );
  }

  const list = playlist.trackIds
    .map((tid) => tracks.find((t) => t.id === tid))
    .filter((t): t is NonNullable<typeof t> => Boolean(t));
  const total = list.reduce((sum, t) => sum + t.duration, 0);

  return (
    <div>
      <AppBar
        title="Playlist"
        eyebrow={playlist.system ? "Collection" : "Your playlist"}
        actions={
          <button className="iconbtn iconbtn--sm" onClick={() => onNavigate({ name: "library" })} aria-label="Back">
            <IconChevronLeft width={16} height={16} />
          </button>
        }
      />

      <div className="phero">
        <div className="phero__art">
          <Cover cover={playlist.cover} seed={playlist.id} />
        </div>
        <div className="phero__body">
          <h1>{playlist.name}</h1>
          <div className="phero__sub">
            {list.length} tracks · {fmtLong(total)}
          </div>
          <div className="phero__desc">{playlist.description}</div>
        </div>
      </div>

      <div className="phero__actions" style={{ marginTop: 0, marginBottom: 18 }}>
        <button className="btn btn--primary" disabled={!list.length} onClick={() => playQueue(list, 0, playlist.name)}>
          <IconPlay width={14} height={14} /> Play
        </button>
        <button
          className="btn"
          disabled={!list.length}
          onClick={() => playQueue([...list].sort(() => Math.random() - 0.5), 0, playlist.name)}
        >
          <IconShuffle width={14} height={14} /> Shuffle
        </button>
        {!playlist.system && (
          <button
            className="btn"
            onClick={() => {
              if (window.confirm(`Delete “${playlist.name}”?`)) {
                deletePlaylist(playlist.id);
                onNavigate({ name: "library" });
              }
            }}
          >
            <IconTrash width={14} height={14} />
          </button>
        )}
      </div>

      {list.length === 0 ? (
        <div className="empty">
          <h3>This playlist is empty</h3>
          <p>Search for something and add it from the player.</p>
          <button className="btn" onClick={() => onNavigate({ name: "search" })}>
            Find music
          </button>
        </div>
      ) : (
        list.map((track) => (
          <div key={track.id} style={{ display: "flex", alignItems: "center", gap: 2 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <TrackRow track={track} list={list} label={playlist.name} />
            </div>
            <button
              className="iconbtn iconbtn--sm"
              aria-label={`Remove ${track.title}`}
              onClick={() => removeFromPlaylist(playlist.id, track.id)}
            >
              <IconX width={13} height={13} />
            </button>
          </div>
        ))
      )}
    </div>
  );
}
