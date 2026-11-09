import type { ReactNode } from "react";

/** Screen header: big tight title on the left, glass actions on the right. */
export function AppBar({
  title,
  eyebrow,
  actions,
}: {
  title: string;
  eyebrow?: string;
  actions?: ReactNode;
}) {
  return (
    <header className="appbar">
      <div>
        {eyebrow && <div className="appbar__eyebrow">{eyebrow}</div>}
        <h1>{title}</h1>
      </div>
      {actions && <div className="appbar__actions">{actions}</div>}
    </header>
  );
}
