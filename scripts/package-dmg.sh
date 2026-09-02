#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Margin.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
NAME="Margin-$VERSION-universal.dmg"
OUTPUT="$ROOT/dist/$NAME"
STAGE="$(mktemp -d /private/tmp/margin-dmg.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

"$ROOT/build.sh"
mkdir -p "$ROOT/dist"
ditto "$APP" "$STAGE/Margin.app"
cp "$ROOT/LICENSE" "$STAGE/LICENSE.txt"
ln -s /Applications "$STAGE/Applications"
hdiutil create -ov -format UDZO -volname "Margin $VERSION" -srcfolder "$STAGE" "$OUTPUT"
hdiutil verify "$OUTPUT"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  [[ -n "${CODE_SIGN_IDENTITY:-}" ]] || { print -u2 "NOTARY_PROFILE requires CODE_SIGN_IDENTITY"; exit 1; }
  xcrun notarytool submit "$OUTPUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUTPUT"
fi

(cd "$ROOT/dist" && shasum -a 256 "$NAME" > "$NAME.sha256")
print "Packaged: $OUTPUT"
