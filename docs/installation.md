# Installation and Releases

TokenAtlas publishes source code, GitHub Releases, and the Sparkle appcast from
the same public repository:

- Repository: <https://github.com/can4hou6joeng4/TokenAtlas>
- Releases: <https://github.com/can4hou6joeng4/TokenAtlas/releases>
- Update feed: <https://can4hou6joeng4.github.io/TokenAtlas/appcast.xml>

## Current Release Status

No public app archive has been published yet. The release workflow is ready, but
the first downloadable build will appear after maintainers push the first semver
tag.

## Installing a Packaged Build

When a release exists:

1. Open the latest GitHub Release.
2. Download `TokenAtlas-<version>.dmg` or `TokenAtlas-<version>.zip`.
3. If you downloaded the DMG, open it and drag `TokenAtlas.app` onto the
   `Applications` shortcut shown in the installer window.
4. If you downloaded the zip fallback, unzip it and move `TokenAtlas.app` into
   `/Applications`.
5. Launch TokenAtlas.

Unsigned preview builds may trigger macOS Gatekeeper. If that happens, right
click `TokenAtlas.app`, choose **Open**, then confirm the launch prompt.

## Automatic Updates

TokenAtlas embeds Sparkle 2. Settings -> About includes **Check for Updates...**,
and scheduled update checks are enabled by default.

Automatic updates require:

- `SUPublicEDKey` in `TokenAtlas/App/Info.plist`.
- `SPARKLE_PRIVATE_ED_KEY` configured as a GitHub Actions secret.
- GitHub Pages serving `appcast.xml` from the `gh-pages` branch.

The current appcast URL is:

```text
https://can4hou6joeng4.github.io/TokenAtlas/appcast.xml
```

## Maintainer Release Flow

Create a release by pushing a semver tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The release workflow builds the app, packages a DMG and zip fallback depending
on signing secrets, uploads release artifacts to GitHub Releases, and updates
the Sparkle appcast when Sparkle signing is configured.

## Local Development Install

For local daily use without publishing a release:

```bash
bash scripts/install-app.sh
```

For development verification, use the canonical debug launcher instead:

```bash
bash scripts/run-debug.sh
```
