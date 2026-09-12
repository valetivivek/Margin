# Releasing Margin

Update the short version and build number in `Info.plist`, then add detailed release notes under a matching `## VERSION - DATE` heading in `CHANGELOG.md`. The release workflow uses that section as the published GitHub release description.

For local development, run:

```sh
./scripts/package-dmg.sh --build-only
```

This creates the isolated, ad-hoc-signed `Margin Dev.app`, which never reads production notes or their encryption key. To update `/Applications/Margin.app` locally, quit Margin and run:

```sh
./scripts/package-dmg.sh --install
```

A failed build leaves the previous verified app intact.

Without arguments, the script builds and checks both architectures, ad-hoc signs the free direct-download app, verifies the app and DMG, and writes a SHA-256 checksum. These releases are not notarized by Apple, so macOS may require users to approve the first launch. Sparkle's separate EdDSA signature authenticates updates.

Push a matching tag such as `v1.4.5`; the release workflow publishes the DMG, checksum, and signed update feed. The repository and its releases must be public because installed copies of Margin cannot authenticate to a private Sparkle feed. The workflow checks this before publishing and verifies the public feed afterward.

Before the first updater-enabled release, export the `com.valetivivek.margin` Sparkle key from Keychain and save it as the repository Actions secret `SPARKLE_PRIVATE_KEY`. Never commit the private key.

```sh
.build/sparkle-2.9.6/bin/generate_keys --account com.valetivivek.margin -x /private/tmp/margin-sparkle-key
gh secret set SPARKLE_PRIVATE_KEY < /private/tmp/margin-sparkle-key
rm /private/tmp/margin-sparkle-key
```

After the workflow succeeds, verify the GitHub release contains the DMG, checksum, and `appcast.xml`; download the public DMG; confirm its checksum; and update the Homebrew cask with that published checksum.

Margin 1.4.5 migrates the note encryption key away from recurring Keychain access. Existing users may receive one final Keychain password prompt while the new version copies the old key to `~/Library/Application Support/Margin/note-body.key`. The legacy Keychain item is retained as a recovery fallback and should not be deleted until the migrated app and notes have been verified.
