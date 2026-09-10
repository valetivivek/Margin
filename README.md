<p align="center">
  <img src="Resources/AppIcon.png" width="112" alt="Margin">
</p>

<h1 align="center">Margin</h1>
<p align="center">Notes that live at the edge of your Mac.</p>
<p align="center">
  <a href="https://github.com/valetivivek/Margin/releases/latest">Download for macOS</a> ·
  <a href="CHANGELOG.md">What’s new</a> ·
  <a href="https://github.com/valetivivek/Margin/issues">Feedback</a>
</p>

## Install

With [Homebrew](https://brew.sh):

```sh
brew install --cask valetivivek/tap/margin
```

Or download the latest [DMG](https://github.com/valetivivek/Margin/releases/latest) and drag Margin into Applications.

**macOS 13+ · Apple silicon & Intel · No account required**

## A little room for your thoughts

- Keep notes on the left, right, or bottom edge of your screen.
- Write with checklists, rich text, or optional Markdown.
- Pin notes to your desktop. Search, archive, and export from All Notes.
- Open your calendars in a dedicated calendar wing.
- Make it yours with note colors, fonts, and light or dark appearance.

Press **⌥⌘N** to capture a note, **⌥⌘L** to open your library, and **⌘,** for Settings. Shortcuts are customizable in **Settings → Shortcuts**.

Updates are available in **Settings → About**. For a Homebrew install:

```sh
brew update
brew upgrade --cask --greedy valetivivek/tap/margin
```

## Your notes stay yours

No analytics, ads, or telemetry. Note bodies and formatting are encrypted locally, with the key stored in macOS Keychain. Titles and metadata are not encrypted. Cloud Sync is currently unavailable; exported files are readable by other apps.

[Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Data deletion](DATA-DELETION.md)

## Build

With Apple developer tools installed:

```sh
./scripts/package-dmg.sh --build-only
```

Creates the verified app at `build/Margin.app`. Use `--install` to build and install after quitting Margin, or omit the flag to package a universal DMG. The first build downloads Sparkle.

[Contributing](CONTRIBUTING.md) · [Architecture](docs/ARCHITECTURE.md) · [Releasing](docs/RELEASING.md) · [MIT license](LICENSE)
