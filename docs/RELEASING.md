# Releasing Margin

Update the short version and build number in `Info.plist`, then add detailed release notes under a matching `## VERSION - DATE` heading in `CHANGELOG.md`. The release workflow uses that section as the published GitHub release description. Public releases must use the same Developer ID Application identity on every build so macOS Keychain recognizes Margin after an update.

Configure these GitHub Actions secrets before releasing:

- `APPLE_CERTIFICATE_BASE64`: a base64-encoded Developer ID Application `.p12`
- `APPLE_CERTIFICATE_PASSWORD`: the `.p12` export password
- `KEYCHAIN_PASSWORD`: a random password used only for the temporary CI keychain
- `APPLE_ID`, `APPLE_APP_PASSWORD`, and `APPLE_TEAM_ID`: notarization credentials

Then run:

```sh
./scripts/package-dmg.sh
```

For local development, use `./scripts/package-dmg.sh --build-only`. It creates the isolated, ad-hoc-signed `Margin Dev.app`, which never reads production notes or their Keychain key.

To update `/Applications/Margin.app` locally, quit Margin and provide a persistent signing identity:

```sh
CODE_SIGN_IDENTITY="Margin Local Development" ./scripts/package-dmg.sh --install
```

An Apple Development or self-signed Code Signing certificate is sufficient for this local-only command, provided every local production build uses the same certificate. It is not suitable for a public release or notarization. A failed build leaves the previous verified app intact.

Without arguments, the script builds and checks both architectures, verifies the app signature and DMG, and writes a SHA-256 checksum. Push a matching tag such as `v1.0.3`; the release workflow publishes the DMG, checksum, and signed update feed.

The repository and its releases must be public before pushing the tag. Installed copies of Margin do not have GitHub credentials, so a feed or DMG hosted in a private release returns `404` and Sparkle cannot update. The release workflow checks this before publishing and verifies the public feed afterward.

Before the first updater-enabled release, export the `com.valetivivek.margin` Sparkle key from Keychain and save it as the repository Actions secret `SPARKLE_PRIVATE_KEY`. The release workflow uses it to sign the update archive and appcast; never commit the private key.

```sh
.build/sparkle-2.9.6/bin/generate_keys --account com.valetivivek.margin -x /private/tmp/margin-sparkle-key
gh secret set SPARKLE_PRIVATE_KEY < /private/tmp/margin-sparkle-key
rm /private/tmp/margin-sparkle-key
```

Ad-hoc signing is limited to the isolated development app. Apple requires a Developer ID Application certificate and notarization for direct public distribution:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="margin-notary" \
./scripts/package-dmg.sh
```

Never commit certificates, passwords, or notarization credentials.

The first Developer ID-signed update replaces the identity used by older ad-hoc releases, so users must choose **Always Allow** once in the Keychain prompt. Later updates signed by the same Developer ID do not require another approval. Do not delete the `app.margin.local-key` item to clear old permissions; it contains the only key capable of decrypting existing note bodies.
