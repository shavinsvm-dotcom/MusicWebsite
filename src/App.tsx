import { useEffect, useRef, useState } from "react";
import type { TabName, View } from "./types";
import { useLibrary } from "./state/library";
import { usePlayer } from "./state/player";
import { TabBar } from "./components/TabBar";
import { PlayerBar } from "./components/PlayerBar";
import { NowPlaying } from "./components/NowPlaying";
import { Discover } from "./views/Discover";
import { Search } from "./views/Search";
import { Library } from "./views/Library";
import { Upload } from "./views/Upload";
import { PlaylistView } from "./views/PlaylistView";
import { ArtistView } from "./views/ArtistView";
import { You } from "./views/You";

export default function App() {
  const { playlists, createPlaylist, addToPlaylist, toasts } = useLibrary();
  const { full, current, togglePlay, seek, time, openFull } = usePlayer();
  const [view, setView] = useState<View>({ name: "discover" });
  const [tab, setTab] = useState<TabName>("discover");
  const [query, setQuery] = useState("");
  const [newPlaylistOpen, setNewPlaylistOpen] = useState(false);
  const [playlistName, setPlaylistName] = useState("");
  const [pickerOpen, setPickerOpen] = useState(false);
  const scrollRef = useRef<HTMLElement>(null);

  function navigate(next: View) {
    setView(next);
    // Detail screens (playlist, artist) keep whatever tab opened them.
    if (next.name !== "playlist" && next.name !== "artist") setTab(next.name);
    scrollRef.current?.scrollTo({ top: 0 });
  }

  function openSearch() {
    navigate({ name: "search" });
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement | null)?.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
      if (e.key === "/") {
        e.preventDefault();
        openSearch();
      } else if (e.key === " ") {
        e.preventDefault();
        togglePlay();
      } else if (e.key === "ArrowRight" && e.shiftKey) {
        seek(time + 10);
      } else if (e.key === "ArrowLeft" && e.shiftKey) {
        seek(time - 10);
      } else if (e.key === "Escape") {
        setPickerOpen(false);
        setNewPlaylistOpen(false);
      } else if (e.key.toLowerCase() === "e" && current) {
        openFull();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [togglePlay, seek, time, current, openFull]);

  const addablePlaylists = playlists.filter((p) => !p.system);

  return (
    <div className="page">
      <div className="device">
        <main className="scroll" ref={scrollRef}>
          {view.name === "discover" && (
            <Discover
              onNavigate={navigate}
              onMood={(mood) => {
                setQuery(mood);
                openSearch();
              }}
            />
          )}
          {view.name === "search" && <Search query={query} setQuery={setQuery} onNavigate={navigate} />}
          {view.name === "library" && (
            <Library onNavigate={navigate} onNewPlaylist={() => setNewPlaylistOpen(true)} />
          )}
          {view.name === "upload" && <Upload onGoLibrary={() => navigate({ name: "library" })} />}
          {view.name === "playlist" && <PlaylistView id={view.id} onNavigate={navigate} />}
          {view.name === "artist" && <ArtistView artist={view.artist} onNavigate={navigate} />}
          {view.name === "you" && <You onNavigate={navigate} />}
        </main>

        <PlayerBar />
        <TabBar active={tab} onNavigate={navigate} onUpload={() => navigate({ name: "upload" })} />

        {full && current && <NowPlaying onAddToPlaylist={() => setPickerOpen(true)} />}
      </div>

      <div className="toasts">
        {toasts.map((toast) => (
          <div key={toast.id} className="toast">
            <i />
            {toast.message}
          </div>
        ))}
      </div>

      {newPlaylistOpen && (
        <div className="scrim" onClick={() => setNewPlaylistOpen(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>New playlist</h3>
            <p>Give it a name. Add tracks from the player or any list.</p>
            <div className="field">
              <label htmlFor="pl-name">Name</label>
              <input
                id="pl-name"
                autoFocus
                value={playlistName}
                onChange={(e) => setPlaylistName(e.target.value)}
                placeholder="Night bus home"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && playlistName.trim()) {
                    const playlist = createPlaylist(playlistName);
                    setPlaylistName("");
                    setNewPlaylistOpen(false);
                    navigate({ name: "playlist", id: playlist.id });
                  }
                }}
              />
            </div>
            <div className="modal__actions">
              <button className="btn btn--ghost" onClick={() => setNewPlaylistOpen(false)}>
                Cancel
              </button>
              <button
                className="btn btn--primary"
                disabled={!playlistName.trim()}
                onClick={() => {
                  const playlist = createPlaylist(playlistName);
                  setPlaylistName("");
                  setNewPlaylistOpen(false);
                  navigate({ name: "playlist", id: playlist.id });
                }}
              >
                Create
              </button>
            </div>
          </div>
        </div>
      )}

      {pickerOpen && current && (
        <div className="scrim" onClick={() => setPickerOpen(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h3>Add to playlist</h3>
            <p>
              “{current.title}” by {current.artist}
            </p>
            <div className="queue" style={{ maxHeight: 260 }}>
              {addablePlaylists.length === 0 && <div className="lyrics__empty">No playlists yet — make one first.</div>}
              {addablePlaylists.map((playlist) => (
                <button
                  key={playlist.id}
                  className="qitem"
                  onClick={() => {
                    addToPlaylist(playlist.id, current.id);
                    setPickerOpen(false);
                  }}
                >
                  <span
                    className="qitem__art"
                    style={{ background: `linear-gradient(135deg, ${playlist.cover.accent}, ${playlist.cover.to})` }}
                  />
                  <span className="qitem__meta">
                    <span className="qitem__t">{playlist.name}</span>
                    <span className="qitem__a">{playlist.trackIds.length} tracks</span>
                  </span>
                </button>
              ))}
              <button
                className="qitem"
                onClick={() => {
                  addToPlaylist("sys-liked", current.id);
                  setPickerOpen(false);
                }}
              >
                <span className="qitem__art" style={{ background: "linear-gradient(135deg,#ff2d8f,#8b5cf6)" }} />
                <span className="qitem__meta">
                  <span className="qitem__t">Liked Songs</span>
                  <span className="qitem__a">Quick save</span>
                </span>
              </button>
            </div>
            <div className="modal__actions">
              <button className="btn btn--ghost" onClick={() => setPickerOpen(false)}>
                Done
              </button>
              <button
                className="btn btn--primary"
                onClick={() => {
                  const playlist = createPlaylist(`Mix ${playlists.length}`);
                  addToPlaylist(playlist.id, current.id);
                  setPickerOpen(false);
                  navigate({ name: "playlist", id: playlist.id });
                }}
              >
                New playlist
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
