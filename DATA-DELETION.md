# Data Deletion and Backups

Last updated: September 8, 2026

## What Delete currently does

Delete hides a note from the library and saves a deletion marker alongside its stored content. Undo is available briefly. The record remains after Undo expires. Archive also retains content. Neither action is secure erasure.

## Remove Margin's local note store

1. Export anything you want to keep. Exports are not encrypted by Margin; protect them separately.
2. Quit Margin so pending edits finish saving and the database is closed.
3. In Finder, choose Go → Go to Folder and open `~/Library/Application Support/Margin/`.
4. Remove that folder, including `notes.sqlite3` and any SQLite journal files. This removes the local store, including archived and deleted records. Only empty Trash after you are certain you no longer need it.
5. If removing Margin completely, its encryption key can also be removed using Keychain Access: find the generic password with service `app.margin.local-key` and account `note-body-key`. **Removing the key can make any remaining encrypted database copies permanently unreadable.**

Preferences are stored under the app's bundle identifier, `com.valetivivek.margin`, in macOS preferences. Removing the app itself does not guarantee that preferences or Keychain items are removed.

Also review your exports, shared copies, operating-system temporary files under `Margin-Exports`, Trash, and backups. Removing the local database cannot recall copies already shared or remove cloud-provider backups. File deletion is not a promise of forensic erasure from SSDs, snapshots, or backups.

## Calendar data

Disable Calendar wing in Settings → Calendar and revoke Calendar access in macOS Privacy & Security settings if desired. Margin does not store a separate calendar-event database. You can delete an event from its edit sheet in Margin; the request is sent through EventKit to its connected calendar account. Providers may retain deleted events in Trash, backups, or according to their own policies, so verify deletion with that service when necessary.

## Restoring notes

The database and its matching Keychain key are both needed to recover encrypted note bodies. Copying only the database to another Mac is insufficient if the key is missing. For portable copies, use Margin's export options and protect the resulting readable files.
