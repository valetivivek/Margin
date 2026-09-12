# Architecture

Margin is a native AppKit application with SwiftUI content. It compiles directly with `swiftc`; Sparkle provides signed automatic updates.

## Source map

| Area | Responsibility |
|---|---|
| `Sources/App` | Process entry point, application delegate, menu-bar item, shortcuts, window controllers, and coordination |
| `Sources/Core` | Models, settings, encrypted SQLite persistence, note operations, and optional folder sync |
| `Sources/UI` | Edge deck, editor, library, settings, onboarding, import, and export |

`AppCoordinator` connects windows to a shared `NotesStore`. `EdgePanelController` owns each screen-edge panel, while `StickyWindowController` owns editable notes. Ordinary edits are debounced and pending text is flushed before a note closes or the app terminates for an update.

Local note bodies are encrypted with AES-GCM before SQLite persistence. The key is stored at `~/Library/Application Support/Margin/note-body.key` with user-only permissions. On the first upgraded launch, Margin copies an existing legacy key from macOS Keychain and retains that item as a recovery fallback. Optional sync owns Markdown conversion, conflict resolution, tombstones, and atomic file writes behind `CloudSyncEngine.sync(local:folder:)`.

Sparkle checks the signed GitHub Releases appcast and installs EdDSA-verified updates. Its automatic checks and downloads are controlled directly through Sparkle's user defaults from **Settings → About**.

The UI uses an adaptive selection palette: a darker blue in light mode, a higher-luminance blue in dark mode, and explicit selected surfaces and borders. Native segmented controls retain their AppKit behavior while applying the same accent per control.

`./scripts/package-dmg.sh` compiles both supported architectures, runs persistence and interaction self-checks, and packages the release disk image.

## Draft and build ownership

`NotesStore.edit(id:)` changes the latest draft synchronously. Views bind fields to that operation; pinning and window movement patch only their own fields. The store owns timestamps and debounced persistence. Flush returns success, retaining failed drafts for retry; editor close and application quit keep unsaved work open on failure.

`package-dmg.sh --build-only` verifies a staged native build before replacing `build/Margin Dev.app`. `--install` builds the production identity and replaces the installed app. The default release mode builds both architectures and packages the verified app. Failed builds preserve the previous app; `python3 scripts/check-build-workflow.py` exercises that guarantee.

Development builds use the name Margin Dev and bundle ID `com.valetivivek.margin.dev`. They automatically use the isolated UI-test store and disable automatic updates. Release artifacts live in `.build/release.noindex` to avoid Spotlight discovery; `/Applications/Margin.app` remains the normal app.
