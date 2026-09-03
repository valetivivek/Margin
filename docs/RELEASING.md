# Releasing Margin

Update the short version and build number in `Info.plist`, update `CHANGELOG.md`, then run:

```sh
./scripts/package-dmg.sh
```

The script builds and checks both architectures, verifies the app signature and DMG, and writes a SHA-256 checksum. Push a matching tag such as `v1.0.2`; the release workflow publishes the DMG, checksum, and signed update feed.

Before the first updater-enabled release, export the `com.valetivivek.margin` Sparkle key from Keychain and save it as the repository Actions secret `SPARKLE_PRIVATE_KEY`. The release workflow uses it to sign the update archive and appcast; never commit the private key.

```sh
.build/sparkle-2.9.6/bin/generate_keys --account com.valetivivek.margin -x /private/tmp/margin-sparkle-key
gh secret set SPARKLE_PRIVATE_KEY < /private/tmp/margin-sparkle-key
rm /private/tmp/margin-sparkle-key
```

Ad hoc signing is suitable for local and public testing but may show a first-launch Gatekeeper prompt. Trusted distribution requires a Developer ID Application certificate and notarization credentials:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="margin-notary" \
./scripts/package-dmg.sh
```

Never commit certificates, passwords, or notarization credentials.
