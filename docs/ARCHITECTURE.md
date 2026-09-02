# Architecture

Margin is a native AppKit application with SwiftUI content. It compiles directly with `swiftc` and has no third-party runtime dependencies.

## Source map

| Area | Responsibility |
|---|---|
| `Sources/App` | Process entry point, application delegate, menu-bar item, shortcuts, window controllers, and coordination |
| `Sources/Core` | Models, settings, encrypted SQLite persistence, note operations, and optional folder sync |
| `Sources/UI` | Edge deck, editor, library, archive, settings, onboarding, import, and export |

`AppCoordinator` connects windows to a shared `NotesStore`. `EdgePanelController` owns each screen-edge panel, while `StickyWindowController` owns editable notes. Ordinary edits are debounced and pending text is flushed before a note closes.

Local note bodies are encrypted with AES-GCM before SQLite persistence. The key is stored in macOS Keychain. Optional sync owns Markdown conversion, conflict resolution, tombstones, and atomic file writes behind `CloudSyncEngine.sync(local:folder:)`.

`./build.sh` compiles both supported architectures and runs persistence and interaction self-checks.
