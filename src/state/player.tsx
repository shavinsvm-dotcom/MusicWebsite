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
import type { RepeatMode, Track } from "../types";
import { useLibrary } from "./library";

type Panel = "lyrics" | "queue" | null;

type PlayerApi = {
  current: Track | null;
  queue: Track[];
  index: number;
  contextLabel: string;
  isPlaying: boolean;
  time: number;
  duration: number;
  volume: number;
  muted: boolean;
  shuffle: boolean;
  repeat: RepeatMode;
  full: boolean;
  panel: Panel;
  playTrack: (track: Track, list?: Track[], label?: string) => void;
  playQueue: (list: Track[], startIndex?: number, label?: string) => void;
  togglePlay: () => void;
  next: () => void;
  prev: () => void;
  seek: (seconds: number) => void;
  setVolume: (v: number) => void;
  toggleMute: () => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;
  openFull: () => void;
  closeFull: () => void;
  setPanel: (p: Panel) => void;
  playById: (id: string, label?: string) => void;
};

const PlayerCtx = createContext<PlayerApi | null>(null);

const LS_VOLUME = "nocturne.volume";

export function PlayerProvider({ children }: { children: ReactNode }) {
  const { tracks, registerPlay } = useLibrary();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const playingIntent = useRef(false);
  const [queueIds, setQueueIds] = useState<string[]>([]);
  const [index, setIndex] = useState(-1);
  const [contextLabel, setContextLabel] = useState("Your library");
  const [isPlaying, setIsPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(() => {
    const raw = Number(localStorage.getItem(LS_VOLUME));
    return Number.isFinite(raw) && raw > 0 ? Math.min(1, raw) : 0.8;
  });
  const [muted, setMuted] = useState(false);
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState<RepeatMode>("off");
  const [full, setFull] = useState(false);
  const [panel, setPanel] = useState<Panel>("lyrics");

  const currentId = index >= 0 ? queueIds[index] : null;
  const current = useMemo(() => (currentId ? tracks.find((t) => t.id === currentId) ?? null : null), [tracks, currentId]);
  const queue = useMemo(
    () => queueIds.map((id) => tracks.find((t) => t.id === id)).filter((t): t is Track => Boolean(t)),
    [queueIds, tracks],
  );

  /* -- audio element wiring ------------------------------------------------ */

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    if (!current) {
      audio.removeAttribute("src");
      audio.load();
      setTime(0);
      setDuration(0);
      return;
    }
    audio.src = current.src;
    audio.load();
    setTime(0);
    setDuration(current.duration || 0);
    registerPlay(current.id);
    if (playingIntent.current) {
      void audio.play().catch(() => setIsPlaying(false));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current?.id, current?.src]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    playingIntent.current = isPlaying;
    if (isPlaying) void audio.play().catch(() => setIsPlaying(false));
    else audio.pause();
  }, [isPlaying, current?.id]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.volume = muted ? 0 : volume;
    audio.muted = muted;
    try {
      localStorage.setItem(LS_VOLUME, String(volume));
    } catch {
      /* ignore */
    }
  }, [volume, muted]);

  useEffect(() => {
    if (!isPlaying) return;
    let raf = 0;
    const tick = () => {
      const audio = audioRef.current;
      if (audio) setTime(audio.currentTime);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [isPlaying]);

  /* -- transport ----------------------------------------------------------- */

  const playQueue = useCallback(
    (list: Track[], startIndex = 0, label = "Your library") => {
      if (list.length === 0) return;
      const safeIndex = Math.max(0, Math.min(startIndex, list.length - 1));
      setQueueIds(list.map((t) => t.id));
      setIndex(safeIndex);
      setContextLabel(label);
      playingIntent.current = true;
      setIsPlaying(true);
    },
    [],
  );

  const playTrack = useCallback(
    (track: Track, list?: Track[], label?: string) => {
      const source = list && list.length ? list : tracks;
      const at = source.findIndex((t) => t.id === track.id);
      if (at === -1) {
        playQueue([track, ...source], 0, label ?? "Singles");
        return;
      }
      const alreadyCurrent = current?.id === track.id;
      if (alreadyCurrent) {
        togglePlayInternal();
        return;
      }
      playQueue(source, at, label);
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [tracks, current?.id, playQueue],
  );

  const togglePlayInternal = useCallback(() => {
    if (!current) {
      const first = tracks[0];
      if (first) playQueue(tracks, 0, "Your library");
      return;
    }
    setIsPlaying((p) => !p);
  }, [current, tracks, playQueue]);

  const togglePlay = togglePlayInternal;

  const step = useCallback(
    (dir: 1 | -1) => {
      setIndex((prev) => {
        if (queueIds.length === 0) return prev;
        if (shuffle && queueIds.length > 1) {
          let next = prev;
          while (next === prev) next = Math.floor(Math.random() * queueIds.length);
          return next;
        }
        const next = prev + dir;
        if (next < 0) return repeat === "all" ? queueIds.length - 1 : 0;
        if (next >= queueIds.length) return repeat === "all" ? 0 : queueIds.length - 1;
        return next;
      });
      playingIntent.current = true;
      setIsPlaying(true);
    },
    [queueIds.length, shuffle, repeat],
  );

  const next = useCallback(() => step(1), [step]);
  const prev = useCallback(() => step(-1), [step]);

  /** Natural end-of-track behaviour differs from a manual skip. */
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;
    const onEnded = () => {
      if (repeat === "one") {
        audio.currentTime = 0;
        void audio.play();
        return;
      }
      const atEnd = index >= queueIds.length - 1;
      if (atEnd && repeat !== "all") {
        setIsPlaying(false);
        setTime(0);
        audio.currentTime = 0;
        return;
      }
      step(1);
    };
    audio.addEventListener("ended", onEnded);
    return () => audio.removeEventListener("ended", onEnded);
  }, [repeat, index, queueIds.length, step]);

  const seek = useCallback((seconds: number) => {
    const audio = audioRef.current;
    const target = Math.max(0, Math.min(seconds, audio?.duration || duration || 0));
    if (audio && Number.isFinite(target)) {
      audio.currentTime = target;
      setTime(target);
    }
  }, [duration]);

  const playById = useCallback(
    (id: string, label?: string) => {
      const list = tracks;
      const at = list.findIndex((t) => t.id === id);
      if (at >= 0) playQueue(list, at, label);
    },
    [tracks, playQueue],
  );

  const api: PlayerApi = {
    current,
    queue,
    index,
    contextLabel,
    isPlaying,
    time,
    duration,
    volume,
    muted,
    shuffle,
    repeat,
    full,
    panel,
    playTrack,
    playQueue,
    togglePlay,
    next,
    prev,
    seek,
    setVolume: (v) => {
      setVolumeState(v);
      setMuted(v === 0);
    },
    toggleMute: () => setMuted((m) => !m),
    toggleShuffle: () => setShuffle((s) => !s),
    cycleRepeat: () => setRepeat((r) => (r === "off" ? "all" : r === "all" ? "one" : "off")),
    openFull: () => setFull(true),
    closeFull: () => setFull(false),
    setPanel,
    playById,
  };

  return (
    <PlayerCtx.Provider value={api}>
      {children}
      <audio
        ref={audioRef}
        onLoadedMetadata={(e) => {
          const el = e.currentTarget;
          if (Number.isFinite(el.duration) && el.duration > 0) setDuration(el.duration);
        }}
        onTimeUpdate={(e) => setTime(e.currentTarget.currentTime)}
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        preload="metadata"
      />
    </PlayerCtx.Provider>
  );
}

export function usePlayer(): PlayerApi {
  const ctx = useContext(PlayerCtx);
  if (!ctx) throw new Error("usePlayer must be used inside <PlayerProvider>");
  return ctx;
}
