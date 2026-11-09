import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { Playlist, Track } from "../types";
import { DEMO_PLAYLISTS, DEMO_TRACKS } from "../data/seed";
import { getBackend, type MusicBackend, type UploadPayload } from "../lib/backend";
import { paletteFor } from "../lib/covers";

const LS_STATE = "nocturne.state.v1";

type Persisted = {
  likes: string[];
  playlists: Playlist[];
  plays: Record<string, number>;
};

function loadPersisted(): Persisted {
  try {
    const raw = localStorage.getItem(LS_STATE);
    if (!raw) return { likes: [], playlists: [], plays: {} };
    const parsed = JSON.parse(raw) as Partial<Persisted>;
    return {
      likes: Array.isArray(parsed.likes) ? parsed.likes : [],
      playlists: Array.isArray(parsed.playlists) ? parsed.playlists : [],
      plays: parsed.plays && typeof parsed.plays === "object" ? parsed.plays : {},
    };
  } catch {
    return { likes: [], playlists: [], plays: {} };
  }
}

export type Toast = { id: number; message: string };

type LibraryApi = {
  demo: Track[];
  uploads: Track[];
  tracks: Track[];
  playlists: Playlist[];
  backend: MusicBackend | null;
  backendError: string | null;
  ready: boolean;
  likes: string[];
  isLiked: (id: string) => boolean;
  toggleLike: (id: string) => void;
  playsFor: (track: Track) => number;
  registerPlay: (id: string) => void;
  playlistById: (id: string) => Playlist | undefined;
  createPlaylist: (name: string, description?: string) => Playlist;
  deletePlaylist: (id: string) => void;
  addToPlaylist: (playlistId: string, trackId: string) => void;
  removeFromPlaylist: (playlistId: string, trackId: string) => void;
  uploadTrack: (payload: UploadPayload, onProgress: (pct: number) => void) => Promise<Track>;
  deleteUpload: (id: string) => Promise<void>;
  storageBytes: number;
  toasts: Toast[];
  notify: (message: string) => void;
};

const LibraryCtx = createContext<LibraryApi | null>(null);

export const LIKED_ID = "sys-liked";
export const UPLOADS_ID = "sys-uploads";

export function LibraryProvider({ children }: { children: ReactNode }) {
  const initial = useRef(loadPersisted());
  const [uploads, setUploads] = useState<Track[]>([]);
  const [likes, setLikes] = useState<string[]>(initial.current.likes);
  const [customPlaylists, setCustomPlaylists] = useState<Playlist[]>(initial.current.playlists);
  const [plays, setPlays] = useState<Record<string, number>>(initial.current.plays);
  const [backend, setBackend] = useState<MusicBackend | null>(null);
  const [backendError, setBackendError] = useState<string | null>(null);
  const [ready, setReady] = useState(false);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastId = useRef(0);

  const notify = useCallback((message: string) => {
    const id = ++toastId.current;
    setToasts((prev) => [...prev.slice(-2), { id, message }]);
    window.setTimeout(() => setToasts((prev) => prev.filter((t) => t.id !== id)), 3000);
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const be = await getBackend();
        const list = await be.list();
        if (cancelled) return;
        setBackend(be);
        setUploads(list);
      } catch (err) {
        if (!cancelled) {
          setBackendError(err instanceof Error ? err.message : "Storage unavailable");
          setBackend(await getBackend());
        }
      } finally {
        if (!cancelled) setReady(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem(LS_STATE, JSON.stringify({ likes, playlists: customPlaylists, plays }));
    } catch {
      /* storage full or blocked — the app still works for this session */
    }
  }, [likes, customPlaylists, plays]);

  const tracks = useMemo(() => [...uploads, ...DEMO_TRACKS], [uploads]);

  const playlists = useMemo<Playlist[]>(() => {
    const liked: Playlist = {
      id: LIKED_ID,
      name: "Liked Songs",
      description: "Everything you tapped the heart on.",
      trackIds: likes,
      cover: { from: "#2a1030", to: "#ff2d75", accent: "#ffb86b", glyph: "♥" },
      createdAt: Date.now(),
      system: "liked",
    };
    const mine: Playlist = {
      id: UPLOADS_ID,
      name: "Your Uploads",
      description: "Files you added to Nocturne.",
      trackIds: uploads.map((t) => t.id),
      cover: { from: "#161022", to: "#8b5cf6", accent: "#22d3ee", glyph: "↑" },
      createdAt: Date.now(),
      system: "uploads",
    };
    return [liked, mine, ...customPlaylists, ...DEMO_PLAYLISTS];
  }, [likes, uploads, customPlaylists]);

  const isLiked = useCallback((id: string) => likes.includes(id), [likes]);

  const toggleLike = useCallback(
    (id: string) => {
      setLikes((prev) => {
        const has = prev.includes(id);
        notify(has ? "Removed from Liked Songs" : "Added to Liked Songs");
        return has ? prev.filter((x) => x !== id) : [id, ...prev];
      });
    },
    [notify],
  );

  const registerPlay = useCallback((id: string) => {
    setPlays((prev) => ({ ...prev, [id]: (prev[id] ?? 0) + 1 }));
  }, []);

  const playsFor = useCallback((track: Track) => track.plays + (plays[track.id] ?? 0), [plays]);

  const playlistById = useCallback((id: string) => playlists.find((p) => p.id === id), [playlists]);

  const createPlaylist = useCallback(
    (name: string, description = "") => {
      const playlist: Playlist = {
        id: `pl-${Date.now().toString(36)}`,
        name: name.trim() || "Untitled playlist",
        description,
        trackIds: [],
        cover: paletteFor(name + Date.now()),
        createdAt: Date.now(),
      };
      setCustomPlaylists((prev) => [playlist, ...prev]);
      return playlist;
    },
    [],
  );

  const deletePlaylist = useCallback(
    (id: string) => {
      setCustomPlaylists((prev) => prev.filter((p) => p.id !== id));
      notify("Playlist deleted");
    },
    [notify],
  );

  const addToPlaylist = useCallback(
    (playlistId: string, trackId: string) => {
      if (playlistId === LIKED_ID) {
        setLikes((prev) => (prev.includes(trackId) ? prev : [trackId, ...prev]));
        notify("Added to Liked Songs");
        return;
      }
      setCustomPlaylists((prev) =>
        prev.map((p) =>
          p.id === playlistId && !p.trackIds.includes(trackId)
            ? { ...p, trackIds: [...p.trackIds, trackId] }
            : p,
        ),
      );
      notify("Added to playlist");
    },
    [notify],
  );

  const removeFromPlaylist = useCallback(
    (playlistId: string, trackId: string) => {
      if (playlistId === LIKED_ID) {
        setLikes((prev) => prev.filter((id) => id !== trackId));
      } else {
        setCustomPlaylists((prev) =>
          prev.map((p) =>
            p.id === playlistId ? { ...p, trackIds: p.trackIds.filter((id) => id !== trackId) } : p,
          ),
        );
      }
      notify("Removed from playlist");
    },
    [notify],
  );

  const uploadTrack = useCallback(
    async (payload: UploadPayload, onProgress: (pct: number) => void) => {
      const be = backend ?? (await getBackend());
      if (!be) throw new Error("No storage backend available");
      const track = await be.upload(payload, onProgress);
      setUploads((prev) => [track, ...prev.filter((t) => t.id !== track.id)]);
      notify(`“${track.title}” is live`);
      return track;
    },
    [backend, notify],
  );

  const deleteUpload = useCallback(
    async (id: string) => {
      const be = backend ?? (await getBackend());
      await be.remove(id);
      setUploads((prev) => prev.filter((t) => t.id !== id));
      setLikes((prev) => prev.filter((x) => x !== id));
      setCustomPlaylists((prev) =>
        prev.map((p) => (p.trackIds.includes(id) ? { ...p, trackIds: p.trackIds.filter((x) => x !== id) } : p)),
      );
      notify("Upload deleted");
    },
    [backend, notify],
  );

  const storageBytes = useMemo(() => uploads.reduce((sum, t) => sum + (t.size ?? 0), 0), [uploads]);

  const value: LibraryApi = {
    demo: DEMO_TRACKS,
    uploads,
    tracks,
    playlists,
    backend,
    backendError,
    ready,
    likes,
    isLiked,
    toggleLike,
    playsFor,
    registerPlay,
    playlistById,
    createPlaylist,
    deletePlaylist,
    addToPlaylist,
    removeFromPlaylist,
    uploadTrack,
    deleteUpload,
    storageBytes,
    toasts,
    notify,
  };

  return <LibraryCtx.Provider value={value}>{children}</LibraryCtx.Provider>;
}

export function useLibrary(): LibraryApi {
  const ctx = useContext(LibraryCtx);
  if (!ctx) throw new Error("useLibrary must be used inside <LibraryProvider>");
  return ctx;
}
