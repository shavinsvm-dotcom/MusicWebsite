import type { View } from "../types";
import { MOODS } from "../lib/covers";
import { useLibrary } from "../state/library";
import { usePlayer } from "../state/player";
import { Cover } from "../components/Cover";

const SearchGlyph = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round">
    <circle cx="10.8" cy="10.8" r="6.4" />
    <path d="m15.6 15.6 4.2 4.2" />
  </svg>
);

function greetingFor(hour: number) {
  if (hour < 5) return "Still up";
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

function Section({
  title,
  onSeeAll,
  children,
}: {
  title: string;
  onSeeAll?: () => void;
  children: React.ReactNode;
}) {
  return (
    <section className="section">
      <div className="section__head">
        <h2>{title}</h2>
        {onSeeAll && (
          <button className="linkmore" onClick={onSeeAll}>
            See All
          </button>
        )}
      </div>
      {children}
    </section>
  );
}

export function Discover({
  onNavigate,
  onMood,
}: {
  onNavigate: (view: View) => void;
  onMood: (mood: string) => void;
}) {
  const { tracks, playlists } = useLibrary();
  const { playQueue } = usePlayer();

  const trending = playlists.filter((p) => !p.system && p.id !== "sys-uploads").slice(0, 3);
  const madeFor = MOODS.slice(0, 3);
  const recent = [...tracks].sort((a, b) => b.createdAt - a.createdAt).slice(0, 3);
  const avatar = playlists.find((p) => p.id === "sys-liked")?.cover ?? playlists[0]?.cover;

  const openPlaylist = (id: string) => onNavigate({ name: "playlist", id });

  return (
    <div className="home">
      <header className="home__head">
        <div>
          <p className="home__greet">{greetingFor(new Date().getHours())}</p>
          <h1 className="home__title">
            Music for
            <br />a better you
          </h1>
        </div>
        <button className="home__avatar" onClick={() => onNavigate({ name: "you" })} aria-label="Your profile">
          {avatar && <Cover cover={avatar} seed="you" />}
        </button>
      </header>

      <button className="searchpill" onClick={() => onNavigate({ name: "search" })}>
        <SearchGlyph />
        <span>Search songs, artists, or albums…</span>
      </button>

      <div className="filters">
        <button className="filter is-on">All</button>
        {MOODS.map((mood) => (
          <button key={mood.name} className="filter" onClick={() => onMood(mood.name)}>
            {mood.name}
          </button>
        ))}
      </div>

      <Section title="Trending now" onSeeAll={() => onNavigate({ name: "library" })}>
        <div className="row3">
          {trending.map((playlist) => (
            <button key={playlist.id} className="scard" onClick={() => openPlaylist(playlist.id)}>
              <span className="scard__art">
                <Cover cover={playlist.cover} seed={playlist.id} />
              </span>
              <span className="scard__t">{playlist.name}</span>
              <span className="scard__s">{playlist.description}</span>
            </button>
          ))}
        </div>
      </Section>

      <Section title="Made for you" onSeeAll={() => onNavigate({ name: "search" })}>
        <div className="row3">
          {madeFor.map((mood) => (
            <button key={mood.name} className="scard" onClick={() => onMood(mood.name)}>
              <span
                className="scard__art"
                style={{
                  background: `linear-gradient(150deg, ${mood.cover.accent}, ${mood.cover.to} 58%, ${mood.cover.from})`,
                }}
              />
              <span className="scard__t">{mood.name}</span>
              <span className="scard__s">{mood.sub}</span>
            </button>
          ))}
        </div>
      </Section>

      <Section title="Recently played" onSeeAll={() => onNavigate({ name: "library" })}>
        <div className="row3">
          {recent.map((track, i) => (
            <button
              key={track.id}
              className="scard"
              onClick={() => playQueue(recent, i, "Recently played")}
            >
              <span className="scard__art">
                <Cover cover={track.cover} seed={track.id} art={track.art} />
              </span>
              <span className="scard__t">{track.title}</span>
              <span className="scard__s">{track.artist}</span>
            </button>
          ))}
        </div>
      </Section>
    </div>
  );
}
