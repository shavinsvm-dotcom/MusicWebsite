# Lilt for iOS

A native SwiftUI music app. No website or web view.

The Xcode project, target, scheme, bundle identifier, app group, URL scheme and
widget kinds remain MOTIF/motif internally so existing installs and shared data
keep working. Lilt is the display name.

## What it does

- Imports audio files from the iPhone’s Files app.
- Searches the public iTunes catalog and plays 30-second Apple Music previews.
- Keeps a local library, favorites, and playlists in the app’s Documents folder.
- Plays in the background with lock-screen controls.
- Uses a native mini player and now-playing screen.

## Requirements

- A Mac with Xcode for direct device installs
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A free Apple ID for personal-device signing

## Generate the Xcode project

From this folder:

```bash
brew install xcodegen   # once
xcodegen generate
open MOTIF.xcodeproj
```

In Xcode:

1. Select the **MOTIF** target → **Signing & Capabilities**.
2. Choose your Apple ID under **Team**.
3. Change the bundle identifier from `com.example.motif` to something unique.
4. Select your iPhone and press **Run**.

Free Apple ID builds expire after 7 days. Re-run from Xcode to renew.

## Cloud Mac: build an unsigned IPA

```bash
chmod +x build-unsigned-ipa.sh
./build-unsigned-ipa.sh
```

This writes `MOTIF.ipa`. Install it with Sideloadly on Windows using a free
Apple ID.

## No Mac at all: GitHub Actions

The repository includes [`.github/workflows/ios-unsigned.yml`](../.github/workflows/ios-unsigned.yml).
On a public GitHub repository, the standard macOS runner is free.

1. Push the repository to GitHub.
2. Open **Actions → Build unsigned iOS IPA → Run workflow**.
3. Download the `MOTIF-unsigned-ipa` artifact.
4. Unzip it and install `MOTIF.ipa` with Sideloadly.

After installation, trust the developer profile on the iPhone:

**Settings → General → VPN & Device Management**

If iOS asks, enable **Settings → Privacy & Security → Developer Mode**, restart,
and confirm.

The free certificate expires after **7 days**; reinstall to renew it.

## Data

The library is stored in the app’s Documents directory. Imported audio is copied
into `Documents/Imported`. Uninstalling the app removes that local data.

The catalog search uses the public iTunes Search API. It requires a network
connection; playback of saved local files does not.
