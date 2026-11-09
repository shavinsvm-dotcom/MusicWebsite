import type { View } from "../types";
import { fmtBytes } from "../lib/format";
import { useLibrary } from "../state/library";
import { useTheme } from "../state/theme";
import { AppBar } from "../components/AppBar";
import { ThemeSwitch } from "../components/ThemeSwitch";

export function You({ onNavigate }: { onNavigate: (view: View) => void }) {
  const { likes, uploads, playlists, storageBytes, backend } = useLibrary();
  const { theme } = useTheme();
  const custom = playlists.filter((p) => !p.system);

  return (
    <div>
      <AppBar title="You" />

      <div className="profile">
        <div className="profile__avatar">YO</div>
        <div>
          <div style={{ fontFamily: '"Space Grotesk", sans-serif', fontSize: 19, fontWeight: 700 }}>You</div>
          <div style={{ fontSize: 11, color: "var(--dim)", marginTop: 2 }}>
            {backend?.kind === "cloud" ? "Cloud listener" : "Local listener"} · no account needed
          </div>
        </div>
      </div>

      <div className="panel" style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
        <div>
          <h2>Appearance</h2>
          <p className="panel__hint" style={{ marginTop: 4 }}>
            {theme === "light" ? "Daylight" : "After hours"}
          </p>
        </div>
        <ThemeSwitch />
      </div>

      <div className="statrow">
        <div className="stat">
          <b>{likes.length}</b>
          <span>Liked</span>
        </div>
        <div className="stat">
          <b>{custom.length}</b>
          <span>Playlists</span>
        </div>
        <div className="stat">
          <b>{uploads.length}</b>
          <span>Uploads</span>
        </div>
      </div>

      <div className="panel">
        <h2>Storage</h2>
        <p className="panel__hint">
          {backend?.kind === "cloud"
            ? `Audio streams from ${backend.label}.`
            : "Audio is saved in this browser only. Connect a free bucket to share it."}
        </p>
        <div className="storagebar">
          <span style={{ width: `${Math.min(100, Math.max(4, (storageBytes / (40 * 1024 * 1024)) * 100))}%` }} />
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span className="muted">
            {fmtBytes(storageBytes)} of your library
          </span>
          <span className={backend?.kind === "cloud" ? "backend" : "backend backend--local"}>
            <i />
            {backend?.kind === "cloud" ? backend.label : "Local vault"}
          </span>
        </div>
      </div>

      <div className="panel">
        <h2>Free file hosting</h2>
        <p className="panel__hint">
          Supabase Storage has a free plan with no card: 1 GB of audio, 50 MB per file. Drop two values into{" "}
          <code>.env</code> and uploads stream from their CDN.
        </p>
        <button className="btn btn--primary" style={{ width: "100%" }} onClick={() => onNavigate({ name: "upload" })}>
          Upload a track
        </button>
        <p className="muted" style={{ marginTop: 10, lineHeight: 1.6 }}>
          Setup: create a public bucket called <code>tracks</code>, add the two storage policies, then set{" "}
          <code>VITE_SUPABASE_URL</code> and <code>VITE_SUPABASE_ANON_KEY</code>. Full steps in the README.
        </p>
      </div>

      <div className="panel">
        <h2>Shortcuts</h2>
        <p className="panel__hint" style={{ marginBottom: 10 }}>
          <code>/</code> search · <code>Space</code> play/pause · <code>Shift + ←/→</code> seek 10 s ·{" "}
          <code>E</code> expand player · <code>Esc</code> close
        </p>
      </div>
    </div>
  );
}
