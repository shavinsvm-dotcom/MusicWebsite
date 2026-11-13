# MOTIF pre-miniplayer backup

Snapshot of the working app before the mini-player design-language redesign.
Created 2026-11-12 18:24. Size: 2.7 MB.

## Restore

From the project root (`/workspace/chats/575febf64c59c03e18dd097a`):

```bash
b="BackUp/pre-miniplayer-2026-11-12-182414"

for f in index.html desktop-view.css liquid-glass.js manifest.json \
         package.json package-lock.json piratify-core.js sw.js worker.js \
         freebuff-site.json wrangler.sites.jsonc; do
  cp -a "$b/$f" .
done

rm -rf dist icons fonts vendor scripts
cp -a "$b/dist" dist
cp -a "$b/icons" icons
cp -a "$b/fonts" fonts
cp -a "$b/vendor" vendor
cp -a "$b/scripts" scripts

# The backup predates the new stylesheet; leaving it would be harmless but stray.
rm -f motif-player.css

npm run build
```

`dist/` in the backup is the last build deployed before the redesign, so the
restore is complete even before rebuilding. Restart the preview/dev server and
deploy the restored build to put the old UI back online.
