# Legal documentation — direct GitHub release

Prepared September 7, 2026. This is a release review checklist, not certification that every jurisdiction's requirements are satisfied.

## Included

- PRIVACY.md: local storage, unencrypted metadata, retained deleted records, exports, calendar access, update traffic, and contact route.
- TERMS.md: MIT-compatible use information; no invented subscription, arbitration, or governing-law terms.
- LICENSE: existing MIT License, unchanged.
- THIRD-PARTY-NOTICES.md and bundled original notices.
- DATA-DELETION.md: what deletion actually does and how users remove local data.
- SECURITY.md: vulnerability-reporting guidance without an unverified private-reporting promise.
- Offline document links in Settings → About.

## Before publishing

- Confirm publisher identity and the public/private contact route. Current publisher is taken from the existing LICENSE. The publisher confirmed the United States and GitHub-only contact. No private support email has been supplied; no jurisdiction-specific compliance assurances are made.
- Review the documents against the exact release binary. Preserve truthful distinctions: bodies are encrypted, metadata is not; note deletion retains content; calendar changes are user initiated; provider synchronization can be delayed.
- Verify bundled-font rights and notices. Satoshi permits application embedding but restricts standalone redistribution; check rights for font files already included in the public source repository. Verify Virgil's embedded license text and provenance. Resolve any restriction before distributing the affected asset.
- Ensure original Sparkle and font notices are present in the app and source distribution. The app's MIT License does not override them.
- Enable a private security-reporting route or publish an appropriate private email before soliciting confidential reports. Never request private notes in public issues.
- Publish the privacy policy at a stable, publicly accessible URL alongside the release and keep the bundled copy consistent. Local changes in this workspace have not been pushed or published automatically.
- Review the terms and policy with qualified counsel for the publisher's location and intended markets if needed; required disclosures depend on those facts. This set does not establish GDPR, CCPA, COPPA, or other jurisdiction-specific compliance.

## If moving to the Mac App Store

The current plan is direct GitHub distribution. A later App Store release needs a separate review of privacy labels, a public policy URL, required-reason API declarations, bundled SDK manifests, sandbox entitlements, and the update mechanism. Do not submit a guessed “data not collected” label or assume this direct-download package is App Store-ready.

## References checked

- [Apple App Review Guidelines, privacy section](https://developer.apple.com/app-store/review/guidelines/): in-app and App Store privacy-policy access for App Store distribution.
- [FTC: Marketing Your Mobile App](https://www.ftc.gov/business-guidance/resources/marketing-your-mobile-app-get-it-right-start): privacy representations must match actual practices.
- [Apple: required-reason API declarations](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api): assess separately for App Store submission.
- [Sparkle customization](https://sparkle-project.org/documentation/customization/): update configuration and optional profiling.
