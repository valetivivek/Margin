# Security Policy

## Reporting a vulnerability

Do not publish exploit details, notes, calendar contents, encryption keys, or database files in a public issue. If GitHub private vulnerability reporting is enabled for this repository, use its Security tab to report privately. Otherwise, open a non-sensitive issue asking the maintainer for a private reporting route; wait for that route before sending confidential details.

Include the affected Margin version, macOS version, impact, and a minimal reproduction using invented data. Do not access another person's data or disrupt services to demonstrate a problem. This policy does not grant authorization to test third-party services or promise a bounty or response deadline.

## Security boundaries

Note bodies and presentation data use AES-GCM with a key stored in Margin's user-only Application Support folder. Older installations migrate their existing macOS Keychain key once and retain that item as a recovery fallback. Any process running as the same macOS user with access to that folder can read the local key, so FileVault, a strong login password, and normal macOS account security remain important. Titles and other database metadata are not encrypted by Margin. Displayed content is decrypted in memory. Exported files and temporary sharing copies are readable. Delete retains a database record; see DATA-DELETION.md.

Calendar access is optional. Margin reads events and saves new events only after the user submits the New Event form. Calendar authentication and provider synchronization are managed by macOS. Updates use Sparkle with the project's configured update-signing key. Free direct-download builds are ad-hoc code signed and are not notarized by Apple, so macOS may require the user to approve the first launch.

## Updates

Reports should identify whether the issue exists in the latest published release. No fixed supported-version or patch-response schedule is currently declared. Security fixes and their availability should be described in release notes without exposing unpatched sensitive details.
