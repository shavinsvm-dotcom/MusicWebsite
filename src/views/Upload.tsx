import { useRef, useState } from "react";
import type { Cover } from "../types";
import { COVER_PRESETS, swatch } from "../lib/covers";
import { fmtBytes, fmtTime, probeAudio, titleFromFile } from "../lib/format";
import { readTags } from "../lib/id3";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { AppBar } from "../components/AppBar";
import { Cover as CoverArt } from "../components/Cover";
import { IconSparkle, IconUpload, IconWave } from "../components/icons";

const ACCEPT = ".mp3,.wav,.m4a,.ogg,.flac,audio/*";
const MAX_BYTES = 50 * 1024 * 1024;
const GENRES = ["Lo-fi", "Synthwave", "Ambient", "Dream pop", "Chillwave", "Indie electronic", "Hip-hop", "House", "Other"];

type Identify = "idle" | "reading" | "tagged" | "untagged";

export function Upload({ onGoLibrary }: { onGoLibrary: () => void }) {
  const { uploadTrack, uploads, backend } = useLibrary();
  const { playTrack } = usePlayer();
  const inputRef = useRef<HTMLInputElement>(null);

  const [file, setFile] = useState<File | null>(null);
  const [duration, setDuration] = useState(0);
  const [title, setTitle] = useState("");
  const [artist, setArtist] = useState("");
  const [album, setAlbum] = useState("Singles");
  const [genre, setGenre] = useState(GENRES[0]);
  const [lyrics, setLyrics] = useState("");
  const [coverIdx, setCoverIdx] = useState(0);
  const [cover, setCover] = useState<Cover>(COVER_PRESETS[0]);
  const [art, setArt] = useState<string | null>(null);
  const [identify, setIdentify] = useState<Identify>("idle");
  const [found, setFound] = useState<string | null>(null);
  const [foundMeta, setFoundMeta] = useState<{ title?: string | null; artist?: string | null } | null>(null);
  const [finding, setFinding] = useState(false);
  const [findError, setFindError] = useState<string | null>(null);
  const [over, setOver] = useState(false);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState<string | null>(null);

  async function acceptFile(next: File) {
    setError(null);
    setFound(null);
    setFoundMeta(null);
    setFindError(null);
    if (next.size > MAX_BYTES) {
      setError(`That file is ${fmtBytes(next.size)} — the limit is 50 MB.`);
      return;
    }
    if (!next.type.startsWith("audio/") && !/\.(mp3|wav|m4a|ogg|flac)$/i.test(next.name)) {
      setError("That doesn't look like audio. Try MP3, WAV, M4A, OGG or FLAC.");
      return;
    }

    setFile(next);
    setIdentify("reading");
    setArt(null);

    const tags = await readTags(next);
    if (tags.title) setTitle(tags.title);
    else setTitle(titleFromFile(next.name));
    if (tags.artist) setArtist(tags.artist);
    if (tags.album) setAlbum(tags.album);
    if (tags.genre) setGenre(tags.genre);
    if (tags.picture) setArt(tags.picture);

    const tagged = Boolean(tags.title || tags.artist || tags.album || tags.picture);
    setIdentify(tagged ? "tagged" : "untagged");
    setDuration(await probeAudio(next));
  }

  async function findArtwork() {
    if (finding) return;
    setFinding(true);
    setFindError(null);
    setFound(null);
    setFoundMeta(null);
    try {
      const params = new URLSearchParams();
      if (artist.trim()) params.set("artist", artist.trim());
      if (title.trim()) params.set("title", title.trim());
      if (!params.toString()) {
        setFindError("Add a title or artist first, then search for artwork.");
        return;
      }
      const res = await fetch(`/api/cover?${params.toString()}`);
      if (!res.ok) throw new Error(`Lookup unavailable (${res.status})`);
      const data = (await res.json()) as {
        cover?: string | null;
        title?: string | null;
        artist?: string | null;
      };
      if (!data.cover) {
        setFindError("No artwork found for that title.");
        return;
      }
      setFound(data.cover);
      setFoundMeta({ title: data.title, artist: data.artist });
    } catch (err) {
      setFindError(err instanceof Error ? err.message : "Lookup failed");
    } finally {
      setFinding(false);
    }
  }

  async function submit() {
    if (!file || busy) return;
    if (!title.trim()) {
      setError("Give the track a title first.");
      return;
    }
    setBusy(true);
    setError(null);
    setProgress(0);
    try {
      const track = await uploadTrack(
        {
          file,
          title: title.trim(),
          artist: artist.trim() || "You",
          album: album.trim() || "Singles",
          genre,
          lyrics: lyrics.trim() ? lyrics.trim() : undefined,
          cover,
          art: art ?? undefined,
          duration: duration || 0,
        },
        setProgress,
      );
      setFile(null);
      setTitle("");
      setLyrics("");
      setArt(null);
      setFound(null);
      setIdentify("idle");
      setDuration(0);
      setProgress(0);
      playTrack(track, uploads.concat(track), "Your uploads");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setBusy(false);
    }
  }

  const identifyLabel =
    identify === "reading"
      ? "Reading tags…"
      : identify === "tagged"
        ? "Identified from the file"
        : identify === "untagged"
          ? "No tags found — using the file name"
          : null;

  return (
    <div>
      <AppBar
        title="Upload"
        actions={
          <span className="iconbtn iconbtn--sm" aria-hidden="true">
            <IconWave width={16} height={16} />
          </span>
        }
      />

      <div
        className={`drop${over ? " drop--over" : ""}`}
        role="button"
        tabIndex={0}
        onClick={() => inputRef.current?.click()}
        onKeyDown={(e) => e.key === "Enter" && inputRef.current?.click()}
        onDragOver={(e) => {
          e.preventDefault();
          setOver(true);
        }}
        onDragLeave={() => setOver(false)}
        onDrop={(e) => {
          e.preventDefault();
          setOver(false);
          const dropped = e.dataTransfer.files?.[0];
          if (dropped) void acceptFile(dropped);
        }}
      >
        <div className="drop__icon">
          <IconUpload />
        </div>
        <h3>{over ? "Drop it" : "Add your track"}</h3>
        <p>Drag a file here, or tap to browse · up to 50 MB</p>
        <div className="drop__wave" aria-hidden="true">
          {Array.from({ length: 24 }).map((_, i) => (
            <span
              key={i}
              style={{ height: `${16 + Math.abs(Math.sin(i * 1.7)) * 80}%`, animationDelay: `${i * 0.06}s` }}
            />
          ))}
        </div>
        <input
          ref={inputRef}
          type="file"
          accept={ACCEPT}
          hidden
          onChange={(e) => {
            const picked = e.target.files?.[0];
            if (picked) void acceptFile(picked);
            e.target.value = "";
          }}
        />
      </div>

      {file && (
        <div className="fileline" style={{ marginTop: 12 }}>
          <span className="drop__icon" style={{ width: 34, height: 34, margin: 0, borderRadius: 11 }}>
            <IconWave width={16} height={16} />
          </span>
          <div className="fileline__meta">
            <div className="fileline__name">{file.name}</div>
            <div className="fileline__sub">
              {fmtBytes(file.size)} · {duration ? fmtTime(duration) : "reading…"}
              {identifyLabel ? ` · ${identifyLabel}` : ""}
            </div>
          </div>
          <button className="btn btn--sm btn--ghost" onClick={() => setFile(null)}>
            Replace
          </button>
        </div>
      )}

      <div className="panel" style={{ marginTop: 14 }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", marginBottom: 12 }}>
          <div style={{ width: 62, height: 62, borderRadius: 16, overflow: "hidden", flex: "none" }}>
            {art ? (
              <img
                src={art}
                alt=""
                style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }}
              />
            ) : (
              <CoverArt
                cover={{ ...cover, glyph: title.trim().charAt(0).toUpperCase() || cover.glyph }}
                seed={title || "new"}
              />
            )}
          </div>
          <div style={{ minWidth: 0 }}>
            <div style={{ fontWeight: 600, fontSize: 13 }}>{title || "Untitled track"}</div>
            <div style={{ color: "var(--dim)", fontSize: 10.5, marginTop: 2 }}>
              {artist || "You"} · {album || "Singles"} · {genre}
            </div>
          </div>
        </div>

        <div className="form">
          <div className="form__row">
            <div className="field">
              <label htmlFor="u-title">Title</label>
              <input id="u-title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Neon Rain" />
            </div>
            <div className="field">
              <label htmlFor="u-artist">Artist</label>
              <input id="u-artist" value={artist} onChange={(e) => setArtist(e.target.value)} placeholder="You" />
            </div>
          </div>
          <div className="form__row">
            <div className="field">
              <label htmlFor="u-album">Album</label>
              <input id="u-album" value={album} onChange={(e) => setAlbum(e.target.value)} placeholder="Singles" />
            </div>
            <div className="field">
              <label htmlFor="u-genre">Genre</label>
              <select id="u-genre" value={genre} onChange={(e) => setGenre(e.target.value)}>
                {GENRES.map((g) => (
                  <option key={g} value={g}>
                    {g}
                  </option>
                ))}
              </select>
            </div>
          </div>

          <div className="field">
            <label>Artwork</label>
            <div className="artrow">
              <button className="btn btn--sm btn--ghost" onClick={() => void findArtwork()} disabled={finding}>
                <IconSparkle width={14} height={14} />
                {finding ? "Searching…" : "Find artwork"}
              </button>
              {art && (
                <button className="btn btn--sm btn--ghost" onClick={() => setArt(null)}>
                  Clear
                </button>
              )}
              {identify === "tagged" && art && <span className="muted">from the file</span>}
            </div>
            {findError && (
              <p className="muted" style={{ margin: "6px 0 0" }}>
                {findError}
              </p>
            )}
            {found && (
              <div className="artrow" style={{ marginTop: 8 }}>
                <img
                  src={found}
                  alt="Found artwork"
                  style={{ width: 46, height: 46, borderRadius: 10, objectFit: "cover", display: "block" }}
                />
                <button
                  className="btn btn--sm"
                  onClick={() => {
                    setArt(found);
                    setFound(null);
                    setFoundMeta(null);
                  }}
                >
                  Use this
                </button>
                <span className="muted" style={{ fontSize: 10.5 }}>
                  {foundMeta?.title ?? "Match"}
                  {foundMeta?.artist ? ` · ${foundMeta.artist}` : ""}
                </span>
              </div>
            )}

            {!art && (
              <>
                <p className="muted" style={{ margin: "0 0 8px" }}>
                  No cover yet.
                </p>
                <div className="coverpick">
                  {COVER_PRESETS.map((preset, i) => (
                    <button
                      key={i}
                      data-on={i === coverIdx}
                      aria-label={`Artwork ${i + 1}`}
                      style={{ background: swatch(preset) }}
                      onClick={() => {
                        setCoverIdx(i);
                        setCover({ ...preset, glyph: title.trim().charAt(0).toUpperCase() || preset.glyph });
                      }}
                    />
                  ))}
                </div>
              </>
            )}
          </div>

          <div className="field">
            <label htmlFor="u-lyrics">Lyrics (optional)</label>
            <textarea
              id="u-lyrics"
              value={lyrics}
              onChange={(e) => setLyrics(e.target.value)}
              placeholder={"One line per line…\nthey appear in the player sheet"}
            />
          </div>

          {error && (
            <div className="fileline" style={{ borderColor: "rgba(255,255,255,0.3)", color: "#fff" }}>
              <span>{error}</span>
            </div>
          )}

          {busy && (
            <div>
              <div className="progress">
                <span style={{ width: `${progress}%` }} />
              </div>
              <p className="muted" style={{ margin: "7px 0 0" }}>
                {progress < 100 ? `Uploading… ${progress}%` : "Finishing up…"}
              </p>
            </div>
          )}

          <button className="btn btn--primary" onClick={() => void submit()} disabled={!file || busy}>
            <IconUpload width={15} height={15} />
            {busy ? "Uploading…" : "Publish track"}
          </button>
          <button className="btn btn--ghost" onClick={onGoLibrary}>
            View library
          </button>
        </div>
      </div>

      <p className="muted" style={{ marginTop: 12, lineHeight: 1.6 }}>
        {backend?.kind === "cloud"
          ? `Streaming from ${backend.label}. Existing bucket files are indexed automatically.`
          : "Files stay in this browser until a bucket is connected. Steps are in the README."}
      </p>
    </div>
  );
}
