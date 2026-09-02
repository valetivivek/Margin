# Releasing Margin

Update the short version and build number in `Info.plist`, update `CHANGELOG.md`, then run:

```sh
./scripts/package-dmg.sh
```

The script builds and checks both architectures, verifies the app signature and DMG, and writes a SHA-256 checksum. Push a matching tag such as `v1.0.1`; the release workflow publishes the DMG and checksum.

Ad hoc signing is suitable for local and public testing but may show a first-launch Gatekeeper prompt. Trusted distribution requires a Developer ID Application certificate and notarization credentials:

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="margin-notary" \
./scripts/package-dmg.sh
```

Never commit certificates, passwords, or notarization credentials.
