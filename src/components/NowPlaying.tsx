import { useEffect, useRef, useState } from "react";
import type { CSSVars } from "../lib/style";
import { photoArt } from "../lib/art";
import { fmtTime } from "../lib/format";
import { cx } from "../lib/cx";
import { lookupLyrics, type LyricLine } from "../lib/lyrics";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { Cover } from "./Cover";
import {
  IconChevronDown,
  IconDownload,
  IconHeart,
  IconLyrics,
  IconMute,
  IconNext,
  IconPause,
  IconPlay,
  IconPlus,
  IconPrev,
  IconQueue,
  IconRepeat,
  IconRepeatOne,
  IconShuffle,
  IconVolume,
} from "./icons";

/**
 * Now playing: circular cover on a violet wash, the track, one scrubber, five
 * transport icons, then the lyrics themselves in the open space.
 */
export function NowPlaying({ onAddToPlaylist }: { onAddToPlaylist: () => void }) {
  const {
    current,
    queue,
    contextLabel,
    isPlaying,
    time,
    duration,
    muted,
    shuffle,
    repeat,
    panel,
    closeFull,
    togglePlay,
    next,
    prev,
    seek,
    toggleMute,
    toggleShuffle,
    cycleRepeat,
    setPanel,
    playQueue,
  } = usePlayer();
  const { isLiked, toggleLike } = useLibrary();

  const [more, setMore] = useState(false);
  const [lyricsOn, setLyricsOn] = useState(true);
  const [lyricLines, setLyricLines] = useState<LyricLine[]>([]);
  const [lyricState, setLyricState] = useState<"loading" | "ready" | "empty">("loading");
  const lyricsRef = useRef<HTMLDivElement>(null);

  const trackId = current?.id;

  useEffect(() => {
    if (!current) return;
    let alive = true;
    setLyricState("loading");
    setLyricLines([]);
    lookupLyrics(current.title, current.artist, current.duration || 0, current.lyrics)
      .then((lines) => {
        if (!alive) return;
        setLyricLines(lines);
        setLyricState(lines.length ? "ready" : "empty");
      })
      .catch(() => {
        if (alive) setLyricState("empty");
      });
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trackId]);

  const art = current ? current.art || photoArt(current.cover, current.id) : "";
  const total = duration || current?.duration || 0;
  const pct = total > 0 ? Math.min(100, (time / total) * 100) : 0;

  const activeLyric = lyricLines.reduce((acc, line, i) => (line.at <= time + 0.2 ? i : acc), 0);
  const windowStart = Math.max(0, Math.min(activeLyric - 2, Math.max(0, lyricLines.length - 5)));
  const visibleLyrics = lyricLines.slice(windowStart, windowStart + 5);

  useEffect(() => {
    if (!lyricsOn) return;
    lyricsRef.current
      ?.querySelector<HTMLElement>(".np__lyrline.is-on")
      ?.scrollIntoView({ block: "nearest" });
  }, [activeLyric, lyricsOn]);

  if (!current) return null;

  const liked = isLiked(current.id);

  return (
    <div className="np" role="dialog" aria-modal="true" aria-label="Now playing">
      <div className="np__bg" style={{ backgroundImage: `url("${art}")` }} />
      <div className="np__veil" />

      <div className="np__top">
        <button className="np__round" onClick={closeFull} aria-label="Close player">
          <IconChevronDown />
        </button>
        <span className="np__label">Now Playing</span>
        <button
          className={cx("np__round", liked && "is-on")}
          onClick={() => toggleLike(current.id)}
          aria-label={liked ? "Unlike" : "Like"}
        >
          <IconHeart filled={liked} />
        </button>
      </div>

      <div className="np__discwrap">
        <div className={cx("np__disc", isPlaying && "is-play")} style={{ backgroundImage: `url("${art}")` }} />
      </div>

      <div className="np__info">
        <div className="np__title">{current.title}</div>
        <div className="np__artist">{current.artist}</div>
      </div>

      <div className="np__seek">
        <input
          className="range"
          type="range"
          min={0}
          max={Math.max(1, total)}
          step={0.1}
          value={Math.min(time, total)}
          style={{ "--pct": `${pct}%` } as CSSVars}
          onChange={(e) => seek(Number(e.target.value))}
          aria-label="Seek"
        />
        <div className="np__times">
          <span>{fmtTime(time)}</span>
          <span>{fmtTime(total)}</span>
        </div>
      </div>

      <div className="np__controls">
        <button
          className={cx("iconbtn", shuffle && "iconbtn--on")}
          onClick={toggleShuffle}
          aria-label="Shuffle"
        >
          <IconShuffle />
        </button>
        <button className="iconbtn" onClick={prev} aria-label="Previous">
          <IconPrev />
        </button>
        <button className="np__play" onClick={togglePlay} aria-label={isPlaying ? "Pause" : "Play"}>
          {isPlaying ? <IconPause /> : <IconPlay />}
        </button>
        <button className="iconbtn" onClick={next} aria-label="Next">
          <IconNext />
        </button>
        <button
          className={cx("iconbtn", repeat !== "off" && "iconbtn--on")}
          onClick={cycleRepeat}
          aria-label={`Repeat ${repeat}`}
        >
          {repeat === "one" ? <IconRepeatOne /> : <IconRepeat />}
        </button>
      </div>

      {lyricsOn && (
        <div className="np__lyr" ref={lyricsRef} aria-live="polite">
          {lyricState === "loading" && <p className="np__lyrmeta">Finding lyrics…</p>}
          {lyricState === "empty" && <p className="np__lyrmeta">No lyrics found for this track.</p>}
          {lyricState === "ready" &&
            visibleLyrics.map((line, i) => {
              const index = windowStart + i;
              return (
                <p key={`${line.at}-${index}`} className={cx("np__lyrline", index === activeLyric && "is-on")}>
                  {line.text}
                </p>
              );
            })}
        </div>
      )}

      <div className="np__actions">
        <button
          className={cx("np__act", panel === "queue" && "is-on")}
          onClick={() => setPanel(panel === "queue" ? null : "queue")}
          aria-label="Up next"
        >
          <IconQueue />
        </button>

        <button
          className={cx("np__lyricpill", lyricsOn && "is-on")}
          onClick={() => setLyricsOn((v) => !v)}
          aria-label={lyricsOn ? "Hide lyrics" : "Show lyrics"}
        >
          Lyrics <IconLyrics width={13} height={13} />
        </button>

        <button className={cx("np__act", more && "is-on")} onClick={() => setMore((v) => !v)} aria-label="More">
          <span className="np__dots">•••</span>
        </button>

        {more && (
          <div className="np__moremenu">
            <button
              onClick={() => {
                toggleMute();
                setMore(false);
              }}
            >
              {muted ? <IconVolume /> : <IconMute />}
              {muted ? "Unmute" : "Mute"}
            </button>
            <button
              onClick={() => {
                setMore(false);
                onAddToPlaylist();
              }}
            >
              <IconPlus />
              Add to playlist
            </button>
            <a
              href={current.src}
              download={`${current.artist} - ${current.title}.mp3`}
              onClick={() => setMore(false)}
            >
              <IconDownload />
              Download
            </a>
          </div>
        )}
      </div>

      {panel === "queue" && (
        <aside className="np__side">
          <div className="np__sidehead">
            <span>Up next</span>
            <button className="iconbtn iconbtn--sm" onClick={() => setPanel(null)} aria-label="Hide panel">
              <IconChevronDown width={15} height={15} />
            </button>
          </div>
          <div className="queue">
            {queue.map((track, i) => (
              <button
                key={track.id + i}
                className={cx("qitem", track.id === current.id && "qitem--on")}
                onClick={() => playQueue(queue, i, contextLabel)}
              >
                <span className="qitem__art">
                  <Cover cover={track.cover} seed={track.id} art={track.art} />
                </span>
                <span className="qitem__meta">
                  <span className="qitem__t">{track.title}</span>
                  <span className="qitem__a">{track.artist}</span>
                </span>
                <span style={{ fontSize: 10, color: "var(--dim)" }}>{fmtTime(track.duration)}</span>
              </button>
            ))}
          </div>
        </aside>
      )}
    </div>
  );
}
