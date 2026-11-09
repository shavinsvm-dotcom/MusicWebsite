import { useState } from "react";
import type { View } from "../types";
import { fmtBytes, fmtLong } from "../lib/format";
import { cx } from "../lib/cx";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { AppBar } from "../components/AppBar";
import { PlaylistCard } from "../components/PlaylistCard";
import { TrackRow } from "../components/TrackRow";
import { IconPlus, IconUpload } from "../components/icons";

type Tab = "playlists" | "liked" | "uploads";

export function Library({
  onNavigate,
  onNewPlaylist,
}: {
  onNavigate: (view: View) => void;
  onNewPlaylist: () => void;
}) {
  const { playlists, tracks, likes, uploads, storageBytes, deleteUpload } = useLibrary();
  const { playQueue } = usePlayer();
  const [tab, setTab] = useState<Tab>("playlists");

  const likedTracks = likes
    .map((id) => tracks.find((t) => t.id === id))
    .filter((t): t is NonNullable<typeof t> => Boolean(t));
  const custom = playlists.filter((p) => !p.system || p.id === "sys-liked");

  return (
    <div>
      <AppBar
        title="Library"
        actions={
          <button className="iconbtn iconbtn--sm" onClick={onNewPlaylist} aria-label="New playlist">
            <IconPlus width={16} height={16} />
          </button>
        }
      />

      <div className="seg">
        {(
          [
            ["playlists", "Playlists"],
            ["liked", `Liked ${likedTracks.length}`],
            ["uploads", `Uploads ${uploads.length}`],
          ] as [Tab, string][]
        ).map(([key, label]) => (
          <button key={key} className={cx(tab === key && "on")} onClick={() => setTab(key)}>
            {label}
          </button>
        ))}
      </div>

      {tab === "playlists" && (
        <>
          <div className="duo">
            {custom.map((playlist) => (
              <PlaylistCard
                key={playlist.id}
                playlist={playlist}
                onOpen={() => onNavigate({ name: "playlist", id: playlist.id })}
              />
            ))}
          </div>
          <button className="btn" style={{ width: "100%", marginTop: 14 }} onClick={onNewPlaylist}>
            <IconPlus width={15} height={15} /> New playlist
          </button>
        </>
      )}

      {tab === "liked" && (
        <>
          <div className="section__head">
            <div>
              <h2 style={{ fontSize: 15 }}>Liked Songs</h2>
              <div className="section__sub">{fmtLong(likedTracks.reduce((s, t) => s + t.duration, 0))}</div>
            </div>
            {likedTracks.length > 0 && (
              <button className="btn btn--sm" onClick={() => playQueue(likedTracks, 0, "Liked Songs")}>
                Play all
              </button>
            )}
          </div>
          {likedTracks.length === 0 ? (
            <div className="empty">
              <h3>Nothing liked yet</h3>
              <p>Tap the heart on any track and it lands here.</p>
              <button className="btn" onClick={() => onNavigate({ name: "discover" })}>
                Browse music
              </button>
            </div>
          ) : (
            likedTracks.map((track) => (
              <TrackRow key={track.id} track={track} list={likedTracks} label="Liked Songs" />
            ))
          )}
        </>
      )}

      {tab === "uploads" && (
        <>
          <div className="section__head">
            <div>
              <h2 style={{ fontSize: 15 }}>Your uploads</h2>
              <div className="section__sub">
                {uploads.length} files · {fmtBytes(storageBytes)}
              </div>
            </div>
            {uploads.length > 0 && (
              <button className="btn btn--sm" onClick={() => playQueue(uploads, 0, "Your uploads")}>
                Play all
              </button>
            )}
          </div>
          {uploads.length === 0 ? (
            <div className="empty">
              <h3>No uploads yet</h3>
              <p>MP3, WAV, M4A or OGG up to 50 MB. Artwork is generated for you.</p>
              <button className="btn btn--primary" onClick={() => onNavigate({ name: "upload" })}>
                <IconUpload width={15} height={15} /> Upload a track
              </button>
            </div>
          ) : (
            uploads.map((track) => (
              <TrackRow
                key={track.id}
                track={track}
                list={uploads}
                label="Your uploads"
                onDelete={(t) => {
                  if (window.confirm(`Delete “${t.title}”? This removes the file from storage.`)) {
                    void deleteUpload(t.id);
                  }
                }}
              />
            ))
          )}
        </>
      )}
    </div>
  );
}
