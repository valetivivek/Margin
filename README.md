# Margin

Margin is a native, local-first sticky-note deck for macOS. Notes stay near a screen edge, open into focused editors, and save automatically.

[Download the latest DMG](https://github.com/valetivivek/Margin/releases/latest)

## Features

- Left, right, or bottom edge docking
- Hover previews and click-to-open notes
- Encrypted local SQLite storage with keys kept in Keychain
- Checklists, clickable links, colors, pinning, search, archive, import, and export
- Optional Markdown folder sync
- Configurable global shortcut and animation speed
- Menu-bar access with an optional Dock icon
- Deck visibility on all displays or only the main display
- Light appearance by default, with system and dark options

## Install

Download the latest `.dmg`, open it, and drag Margin into Applications. Public builds are ad hoc signed, so macOS may require Control-clicking Margin and choosing **Open** the first time.

Margin requires macOS 13 or newer.

## Build from source

A full Xcode installation is required.

```sh
./build.sh
```

The build is universal for Apple Silicon and Intel and runs the built-in checks before completing.

To create a local DMG:

```sh
./scripts/package-dmg.sh
```

See [Architecture](docs/ARCHITECTURE.md), [Releasing](docs/RELEASING.md), [Privacy](PRIVACY.md), and [Contributing](CONTRIBUTING.md).

## License

Margin is available under the [MIT License](LICENSE).
