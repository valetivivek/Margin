# Margin Privacy Policy

Last updated: September 12, 2026

This policy covers the Margin macOS app distributed through the [Margin GitHub repository](https://github.com/valetivivek/Margin) and its direct-download releases. The project is maintained by Vivek Valeti, based in the United States. It does not cover independent forks or services you open from the app.

## At a glance

Margin does not require an account and does not include advertising, analytics, or behavioural tracking. Note content is processed locally. Optional calendar access uses macOS Calendar accounts. Update checks contact GitHub and its delivery infrastructure.

## Notes and preferences

Margin stores notes in `~/Library/Application Support/Margin/notes.sqlite3`, with associated SQLite journal files. Note bodies and presentation data, including rich-text formatting, are encrypted using AES-GCM. The key is stored beside the database as `note-body.key`; Margin restricts the folder and key file to the current macOS user. When upgrading from an older release, Margin reads the previous key from macOS Keychain once, copies it to the local key file, and retains the Keychain item as a recovery fallback. **The entire database is not encrypted:** note titles, identifiers, timestamps, colour identifiers, archive/deletion state, ordering, and window positions are stored as metadata without application-level encryption.

Preferences such as theme, shortcuts, calendar-wing placement, and editor settings are stored using macOS preferences. Margin must decrypt note bodies in memory to display or edit them. Device backups, other software with sufficient access, and your operating-system security settings affect protection of local files.

## Optional calendar access

When you choose Allow calendar access, Margin asks macOS for calendar permission. Recent macOS versions describe this as full calendar access because EventKit requires that permission to read and change events. Margin displays events from the calendars you select. It creates, edits, or deletes an event only when you choose the corresponding action and confirms deletion before proceeding. Margin does not send invitations or respond to invitations.

Margin reads calendar/account display names, calendar identifiers and colours, and event information such as titles, dates, times, and locations to display the month grid and day details. When you add or edit an event, Margin sends its title, dates, all-day setting, and chosen calendar to EventKit on your Mac. When you confirm deletion, Margin asks EventKit to remove that event. Calendar data is not written into Margin's note database. Margin does not receive your Google, Apple, or other calendar-account password and does not implement separate provider sign-in.

macOS and your chosen calendar provider manage account synchronization under their own policies. Event additions, edits, and deletions made through Margin may sync to the selected provider. Disabling Calendar wing closes its window. You can revoke permission in System Settings → Privacy & Security → Calendars. Disabling the wing does not itself revoke macOS permission or delete provider events.

## Updates and network requests

The direct-download app uses Sparkle to check the configured GitHub Releases feed and download updates. Network requests necessarily disclose the requesting IP address and ordinary request information, such as a user agent that can identify app or operating-system versions, to GitHub and relevant delivery services. Their logging and retention are governed by their policies; Margin does not control those logs.

Margin does not attach your notes or calendar events to update requests. Sparkle can support optional system-profile reporting; this release does not enable it by default. You can disable automatic updates in Settings → About. Choosing Check Now still makes an update request.

Links you open, files you share, and calendar-account synchronization can involve other services. See [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement), [Apple's privacy policy](https://www.apple.com/legal/privacy/), and your calendar provider's policy for their practices.

## Import, export, sharing, and clipboard

Margin reads files you choose to import. Exported Markdown, text, and archive files are not encrypted by Margin, even if the source note body is encrypted locally. Sharing and dragging notes can create readable temporary files under the operating system's temporary directory in `Margin-Exports`. The app does not guarantee immediate deletion of those temporary copies.

Copying content places it on the system clipboard. Files and clipboard contents may become available to the apps, people, destinations, backup tools, or synchronization services you choose. Folder-based note Cloud Sync is unavailable in this release; existing external copies from earlier versions remain where you saved them.

## Retention and deletion

Notes and preferences remain on your Mac until removed. Archiving retains a note. **Delete removes a note from the visible library but retains its stored record and content with a deletion marker.** The short Undo period is not a permanent-erasure deadline. Uninstalling the application alone does not necessarily remove its database, local encryption key, legacy Keychain entry, preferences, exported files, or backups.

For local removal instructions, read [Data deletion and backups](DATA-DELETION.md). Margin has no app account or developer-hosted note database to delete. Calendar events can be edited or deleted through Margin, macOS Calendar, or their provider.

## Support and privacy requests

If you contact the maintainer, the information you voluntarily provide is handled through that contact service. The public contact route is GitHub only. GitHub issues are public: do not post note contents, calendar details, credentials, database files, or other confidential information. Use the [project's issue tracker](https://github.com/valetivivek/Margin/issues) for non-sensitive questions or to request a private contact route without including sensitive details.

Depending on applicable law, you may have rights regarding personal information handled in support communications. Contact the maintainer to make a request. Margin's local files remain under your control; the maintainer cannot remotely retrieve or erase them. No fixed support-response or legal-response period is promised by this policy.

## Changes

Material changes to these practices should be reflected in this policy and the release notes before the changed behaviour is distributed. The date above identifies this version of the policy.
