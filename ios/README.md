# MOTIF iOS wrapper

A small SwiftUI + `WKWebView` app that hosts the hosted MOTIF site. It is
separate from the web build and does not affect the PWA.

The start URL is `MOTIFStartURL` in [Support/Info.plist](Support/Info.plist).
Change it if the site moves.

## Requirements

- A Mac with Xcode (local or cloud)
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
2. Choose your Apple ID under **Team** (a Personal Team is fine).
3. Change the bundle identifier from `com.example.motif` to something unique,
   for example `com.yourname.motif`.
4. Select your iPhone and press **Run**.

On the iPhone, enable **Developer Mode** if prompted, then trust the developer
in **Settings → General → VPN & Device Management**.

Free Apple ID builds expire after **7 days**. Re-run from Xcode to renew.

## Cloud Mac: build an unsigned IPA

A cloud Mac cannot see a physically connected iPhone, so build an unsigned
`.ipa` there and install it with Sideloadly on your own computer.

```bash
chmod +x build-unsigned-ipa.sh
./build-unsigned-ipa.sh
```

The script runs XcodeGen, builds the device app with code signing disabled, and
writes `MOTIF.ipa`.

## No Mac at all: GitHub Actions

The repository includes [`.github/workflows/ios-unsigned.yml`](../.github/workflows/ios-unsigned.yml).
On a **public** GitHub repository, standard macOS runners are free.

1. Push this repository to GitHub as a public repo.
2. Open the **Actions** tab and choose **Build unsigned iOS IPA**.
3. Click **Run workflow**.
4. Download the `MOTIF-unsigned-ipa` artifact when it finishes.
5. Unzip it and install `MOTIF.ipa` with Sideloadly.

Codemagic is a reasonable alternative if you prefer its UI: its individual plan
currently includes 500 free macOS M2 build minutes per month.

Then, on Windows:

1. Install Sideloadly and the Apple device drivers/iTunes.
2. Connect the iPhone and trust the computer.
3. Drag `MOTIF.ipa` into Sideloadly.
4. Sign in with your free Apple ID and start the install.
5. Trust the developer profile on the phone.

The free certificate still expires after 7 days; reinstall to renew it.

## Notes and limits

- The app loads the hosted site, so it needs a network connection unless the
  WKWebView manages to use its own cache. This wrapper does not promise the
  PWA's offline behavior.
- `UIBackgroundModes: audio` and a playback audio session are configured, but
  lock-screen controls and background playback can still vary in WKWebView.
- Free signing is limited to personal use: no push notifications, limited app
  count, and weekly expiry.
- To remove this wrapper entirely, delete the `ios/` folder. It is not part of
  the web build.
