export type Cover = {
  /** Base colour painted underneath the gradient layers. */
  from: string;
  /** Second gradient stop. */
  to: string;
  /** Highlight colour used for the inner glow + placeholders. */
  accent: string;
  /** Short glyph printed on the artwork. */
  glyph?: string;
};

export type Track = {
  id: string;
  title: string;
  artist: string;
  album: string;
  genre: string;
  /** Seconds. */
  duration: number;
  /** Playable URL (blob URL for local uploads, /api/audio/:id in the cloud). */
  src: string;
  /** Optional real artwork (embedded ID3 picture or a found cover, as a URL/data URL). */
  art?: string;
  cover: Cover;
  lyrics?: string;
  plays: number;
  createdAt: number;
  source: "demo" | "upload";
  size?: number;
  mime?: string;
};

export type Playlist = {
  id: string;
  name: string;
  description: string;
  trackIds: string[];
  cover: Cover;
  createdAt: number;
  /** Built-in lists cannot be renamed or deleted. */
  system?: "liked" | "uploads";
};

export type View =
  | { name: "discover" }
  | { name: "search" }
  | { name: "library" }
  | { name: "upload" }
  | { name: "playlist"; id: string }
  | { name: "artist"; artist: string }
  | { name: "you" };

/** The five bottom-bar destinations. Detail screens keep the tab that opened them. */
export type TabName = "discover" | "search" | "upload" | "library" | "you";

export type RepeatMode = "off" | "all" | "one";

/** What the identifier can pull out of an audio file. */
export type AudioTags = {
  title?: string;
  artist?: string;
  album?: string;
  genre?: string;
  year?: string;
  /** Embedded cover art as a data URL. */
  picture?: string;
};
