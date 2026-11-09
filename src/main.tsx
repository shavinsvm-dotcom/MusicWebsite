import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { LibraryProvider } from "./state/library";
import { PlayerProvider } from "./state/player";
import { ThemeProvider } from "./state/theme";
import { registerServiceWorker } from "./pwa";
import "./styles/global.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <LibraryProvider>
        <PlayerProvider>
          <App />
        </PlayerProvider>
      </LibraryProvider>
    </ThemeProvider>
  </StrictMode>,
);

registerServiceWorker();
