/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Supabase project URL, e.g. https://abcdefgh.supabase.co */
  readonly VITE_SUPABASE_URL?: string;
  /** Supabase publishable (anon) key — safe to ship in the browser. */
  readonly VITE_SUPABASE_ANON_KEY?: string;
  /** Public Storage bucket for audio. Defaults to "tracks". */
  readonly VITE_SUPABASE_BUCKET?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
