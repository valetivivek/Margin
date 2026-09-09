# Security Policy

## Reporting a vulnerability

Do not publish exploit details, notes, calendar contents, encryption keys, or database files in a public issue. If GitHub private vulnerability reporting is enabled for this repository, use its Security tab to report privately. Otherwise, open a non-sensitive issue asking the maintainer for a private reporting route; wait for that route before sending confidential details.

Include the affected Margin version, macOS version, impact, and a minimal reproduction using invented data. Do not access another person's data or disrupt services to demonstrate a problem. This policy does not grant authorization to test third-party services or promise a bounty or response deadline.

## Security boundaries

Note bodies and presentation data use AES-GCM with a key in macOS Keychain. Titles and other database metadata are not encrypted by Margin. Displayed content is decrypted in memory. Exported files and temporary sharing copies are readable. Delete retains a database record; see DATA-DELETION.md.

Calendar access is optional. Margin reads events and saves new events only after the user submits the New Event form. Calendar authentication and provider synchronization are managed by macOS. Updates use Sparkle with the project's configured update-signing key. Developer ID signing, notarization, and release-hosting security must be verified for each public release; a local development build is not evidence of notarization.

## Updates

Reports should identify whether the issue exists in the latest published release. No fixed supported-version or patch-response schedule is currently declared. Security fixes and their availability should be described in release notes without exposing unpatched sensitive details.
