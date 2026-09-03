<p align="center">
  <img src="Resources/AppIcon.png" width="144" alt="Margin app icon">
</p>

<h1 align="center">Margin</h1>

<p align="center"><strong>Notes that live at the edge of your Mac.</strong></p>

<p align="center">
  A native, local-first sticky-note deck that stays close when you need it<br>
  and disappears when you do not.
</p>

<p align="center">
  <a href="https://github.com/valetivivek/Margin/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/valetivivek/Margin?style=flat-square&color=2383e2"></a>
  <img alt="macOS 13 or newer" src="https://img.shields.io/badge/macOS-13%2B-111111?style=flat-square&logo=apple">
  <img alt="Universal binary" src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-111111?style=flat-square">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-31a66a?style=flat-square"></a>
  <a href="https://github.com/valetivivek/Margin/actions/workflows/build.yml"><img alt="Build status" src="https://github.com/valetivivek/Margin/actions/workflows/build.yml/badge.svg"></a>
</p>

<p align="center">
  <a href="https://github.com/valetivivek/Margin/releases/latest"><strong>Download the latest DMG →</strong></a>
</p>

---

## Why Margin?

| Always within reach | Private by default | Made for macOS |
| --- | --- | --- |
| Dock the deck on the left, right, or bottom edge and reveal it with the pointer. | Notes live in encrypted local storage, with the key protected by Keychain. | A lightweight native app with menu-bar mode, global shortcuts, and a universal binary. |

## Everything you need, nothing you do not

- **Fast capture** — press `⌥⌘N` from anywhere to create a note.
- **Edge deck** — hover for a preview, click to write, and drag to reorder.
- **Focused editor** — autosave, checklists, clickable links, colors, and pinning.
- **Full library** — search, archive, restore, import, and export your notes.
- **Your displays, your choice** — show Margin on every display or only the main one.
- **Automatic updates** — receive signed releases automatically, or manage updates in **Settings → Info → About**.
- **Optional sync** — write readable Markdown files to a folder you control.
- **Quiet when needed** — keep Margin in the menu bar without a Dock icon.
- **Comfortable in any theme** — light by default, with system and dark appearances plus high-contrast selected states.

## Quick start

1. [Download the latest DMG](https://github.com/valetivivek/Margin/releases/latest).
2. Open it and drag **Margin** into **Applications**.
3. Control-click Margin and choose **Open** on first launch if macOS shows a security prompt.

Margin requires macOS 13 Ventura or newer.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌥⌘N` | Create a new note from anywhere |
| `⌥⌘L` | Open the complete note library |
| `Esc` or `⌘W` | Save and close the current note |
| `⌘.` | Cycle the current note color |
| `⌘⌫` | Delete the current note |

The quick-capture shortcut and its action can be changed in **Settings → Shortcuts**.

## Settings

Open **Settings** from the Margin menu-bar icon:

- **General** controls the screen edge, fan behavior, and animation speed.
- **Notes** controls type, text size, and the default note color.
- **Cloud Sync** selects and manages an optional Markdown folder.
- **Shortcuts** changes the global shortcut and its action.
- **System** controls Dock and display behavior, full-screen access, and note locking.
- **Appearance** switches between light, system, and dark themes.
- **Info → About** shows the public app version and contains **Automatic updates** and **Check Now**.

Selected tabs, options, filters, and rows use a blue accent together with borders, checkmarks, or font weight so selection remains clear in dark mode and does not rely on color alone.

## Privacy

No account, analytics, advertising, or telemetry. Local notes are encrypted on your Mac. Folder sync is optional and off by default; when enabled, its Markdown files are readable so other apps can use them.

Read the complete [privacy notes](PRIVACY.md).

## Build from source

A full Xcode installation and internet access on the first build are required. The build downloads a pinned, checksum-verified copy of Sparkle for signed automatic updates.

```sh
./scripts/package-dmg.sh
```

The script builds a universal app, runs the built-in checks, and packages a local DMG.

See [Architecture](docs/ARCHITECTURE.md), [Releasing](docs/RELEASING.md), and [Contributing](CONTRIBUTING.md).

## License

Margin is open source under the [MIT License](LICENSE).
