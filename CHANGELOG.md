# Changelog

## 1.4.2 - 2026-09-10

- Fixed note window cleanup during deletion so other notes remain available and new notes can be created afterward.
- Added calendar reminder choices from the event start time to one day before, with a default of 10 minutes for new events. Alerts use macOS Calendar notifications.
- Preserved existing custom and multiple calendar reminders unless explicitly changed.
- Added regression checks for deleting and creating notes, preserving other stored notes, and reminder timing.

Requires macOS 13 or later. Supports Apple silicon and Intel Macs.

## 1.4.1 - 2026-09-10

- Refined the README with real product screenshots and clearer installation guidance.
- Improved note title contrast and weight in the edge deck for easier scanning on hover.
- Hardened the development build workflow with an isolated Margin Dev identity.

Requires macOS 13 or later. Supports Apple silicon and Intel Macs.

## 1.4.0 - 2026-09-09

- Redesigned Settings with a left sidebar, clearer sections, and a live appearance preview. Scrolling works without visible scrollbars.
- Simplified Privacy & legal controls and combined archived notes into the All Notes library.
- Centralized note drafts and saving so pinning, moving, and formatting preserve pending edits. Failed saves retain drafts for retry and prevent closing unsaved work.
- Added a verified build workflow that preserves the current app when compilation fails, with separate development, install, and release modes.

Requires macOS 13 or later. Supports Apple silicon and Intel Macs.

## 1.3.0 - 2026-09-08

Margin 1.3.0 adds a full calendar wing, native rich-text formatting, automatic bullets, note colors and icons, and a tighter Settings layout.

### Calendar wing

- Added a movable, resizable full-month calendar that opens from its own deck wing.
- Display events from multiple iCloud, Google, Exchange, or other accounts connected through macOS Calendar.
- Choose a primary calendar for new events, or select another destination while adding or editing an event.
- Add, edit, move, and delete events through EventKit; macOS handles synchronization with the connected provider.
- Place the wing at the top or bottom, drag it between notes, turn it off completely, and choose its color in Settings.
- Kept the calendar out of the collapsed capsule, removed its dark outer border, and added a confirmed delete action.

### Writing and note appearance

- Markdown is off by default. Command-B and Command-I now toggle native bold and italic formatting without inserting Markdown markers.
- Added Body and Heading 1–3 formatting for selected text, with persistent rich-text storage.
- Typing `-` followed by Space creates a bullet; Enter continues the list and a second Enter ends it without shrinking the text.
- Corrected checklist checkbox baselines, hanging indentation, bullet size, note font sizing, and dark-appearance text color.
- Added note color presets, a custom new-note color picker in Settings, and symbol grids for notes and the menu bar.

### Deck and Settings

- Removed hover jitter and simplified the deck reveal motion while keeping card dragging smooth.
- Brightened wing guide lines and refined the note action toolbar alignment and colors.
- Reorganized Settings into equal-size, single-page tabs without scrollbars, oversized page headings, or redundant section labels.
- Added bundled privacy, terms, data-deletion, security, license, and third-party notices for direct GitHub distribution.

Requires macOS 13 or later. The universal DMG supports Apple silicon and Intel Macs. Calendar access is optional and managed by macOS; Cloud Sync remains paused.

## 1.2.1 - 2026-09-06

Margin 1.2.1 refreshes Settings with a warm oyster palette, Satoshi typography, and a single page for each tab.

- Integrated the window header and simplified the layout, with consistent sliders, dropdowns, and shortcut controls.
- Added five Settings accent colors and clearer controls for cycling or choosing a fixed new-note color.
- Made the live preview reflect your notes, typeface, text size, Markdown formatting, and new-note colors. Saved preferences carry over automatically.
- Enabled **Show over full-screen apps** by default for new preferences. Existing choices are preserved, and turning it off now hides the deck correctly over Helium.
- Improved Markdown preview and source editing, with an adjustable idle delay and formatted deck previews.
- Added individual shortcut toggles, hold-and-scroll deck reordering, and smoother deck positioning. An empty deck shows only **+**; new installations start in menu-bar mode.

Requires macOS 13 or later. The universal DMG supports Apple silicon and Intel Macs; signed automatic updates remain available under **Settings → About**. Cloud Sync remains paused.

## 1.1.0 - 2026-09-05

Margin 1.1.0 adds direct deck positioning, automatic Markdown formatting and file sharing, configurable keyboard shortcuts, and more control over where and when the deck appears. It also restores the familiar edge-attached note preview and refines editor alignment.

### Move the deck directly

- A dotted drag grip now sits below **+**. Drag it to slide the deck along its current edge, or move it to the **left, right, or bottom** of a display.
- An animated docking highlight appears near a supported edge so you can see where the deck will land before releasing it.
- Releasing in the middle of the screen or another unsupported area returns the deck to its previous position without saving an invalid location.
- The grip is translucent white at rest and becomes solid white with thicker dots and a subtle highlight on hover.
- Hovered note cards use the earlier tucked geometry again, keeping them visually connected to the screen edge.
- A narrower, **12-point collapsed activation strip** reduces accidental reveals. The new **Settings → General → Activation delay** slider runs from **0 to 1 second**, with a **50 ms default**.

### Markdown that formats as you type

- Type headings such as `## Test` and the heading receives formatting automatically while the Markdown markers disappear from view.
- Formatting includes heading levels 1–6, bold, italic, strikethrough, links, inline code, code blocks, and block quotes. Table content receives monospaced styling.
- Markdown source stays intact for editing, undo, and export. Turn **Markdown formatting** off in **Settings → Notes** to view the source markers again.
- Checklist boxes and task text now share consistent baselines and spacing across font choices and sizes; wrapped task text aligns with the first line.
- Checklist-looking text inside code remains literal code. Links immediately following a checklist retain their correct visible label.

### Share notes as Markdown files

- Drag a deck card to the Desktop or a Finder folder to create a `.md` copy named after the note, for example `Launch_plan.md`. The original note remains in Margin.
- The note toolbar now includes a native **Share** button for sharing that note as a Markdown file. Its visibility can be toggled in **Settings → Notes → Show Share button**.
- Export filenames are sanitized and use a single `.md` extension, including when the note title already ends in `.md`.
- Share, move, and pin controls now use equal-sized slots, centered icons, consistent spacing, and matching muted styling.

### Displays and settings

- **Settings → General → Display** lets you choose the main display, a specific connected display, or all displays. If a selected display is disconnected, Margin falls back to the main display.
- The default display selection is now **main display only**, and the default note font is **Helvetica**. Previously saved font and display selections remain available.
- Settings windows can be resized. Selected sidebar menus use an accent highlight without an additional checkmark.
- Margin now appears in the Dock and **⌘-Tab** by default, including on the first launch after this update. Turn off **Settings → System → Show in Dock** to return to menu-bar-only operation.

### Configurable keyboard shortcuts

Customize these bindings in **Settings → Keyboard**. Duplicate bindings are rejected, and Escape cancels shortcut recording.

| Default shortcut | Action |
| --- | --- |
| **⌥⌘N** | Quick capture; creates a new note by default |
| **⌥⌘L** | Open All Notes |
| **⌥⌘A** | Open the Archive |
| **⌥⌘E** | Cycle the deck between left, right, and bottom |
| **⌃⌥⌘H** | Hide or show the deck and note windows |
| **⌘,** | Open Settings while a Margin window is active, including from a note |
| **⌘W** | Close the current note, All Notes, Archive, or Settings window |

The All Notes and Archive defaults are now **⌥⌘L** and **⌥⌘A**, respectively. The quick-capture action is configurable separately from its key binding.

### Cloud Sync availability

**Cloud Sync is temporarily disabled in this release.** Its settings entry is dimmed and cannot be opened, and background folder sync does not run. Existing local notes remain available; Markdown export and sharing continue to work. This release does not add Google Drive or Google Keep integration.

### Download and update

- Requires **macOS 13 Ventura or later**; the universal DMG supports both **Apple silicon and Intel Macs**.
- Download `Margin-1.1.0-universal.dmg`, or use **Settings → Info → About → Check Now** in an installed copy.
- Release assets include the DMG, its **SHA-256 checksum**, and the **signed Sparkle update feed** for automatic updates.

## 1.0.3 - 2026-09-03

- Preserve the last editor position when a note closes instead of recording the close animation.
- Flush pending edits before Margin quits or relaunches to install an update.
- Draw completed checklist checkmarks in the correct direction.
- Show only the public app version in About while retaining the internal build number for update ordering.
- Fail release validation when update downloads would be inaccessible to installed apps.
- Make selected tabs, options, rows, filters, and toggles clearly visible in dark mode with an accessible blue accent.
- Move automatic-update controls from System to the Info tab.

## 1.0.2 - 2026-09-02

- Reopen the last-used note at its saved screen position when Margin launches.
- Added signed automatic updates, enabled by default with an opt-out in Settings.

## 1.0.1 - 2026-09-02

- Fixed pointer clicks on expanded edge-deck notes by routing the full visible hover target through note activation.
- Added a setting to show the deck on every display or only the main display.
- Refreshed the public repository and release packaging.

## 1.0.0 - 2026-09-02

- First public release of Margin.
- Added edge and bottom docking, note previews, encrypted local storage, autosave, checklists, links, search, archive, import, export, and pinning.
- Added optional Markdown folder sync, customizable appearance and shortcuts, menu-bar mode, and optional Dock visibility.
- Added universal macOS builds, a DMG release workflow, and the Margin app icon.
