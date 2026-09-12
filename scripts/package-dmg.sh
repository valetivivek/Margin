#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
MODE="${1:-release}"
case "$MODE" in
  release|--build-only|--install) ;;
  *) print -u2 "Usage: $0 [--build-only | --install]"; exit 2 ;;
esac
[[ $# -le 1 ]] || { print -u2 "Expected at most one build mode"; exit 2; }
if [[ "$MODE" != --build-only && -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  print -u2 "Production builds require CODE_SIGN_IDENTITY so Keychain access survives app updates."
  exit 1
fi
if [[ "$MODE" == release && -z "${NOTARY_PROFILE:-}" ]]; then
  print -u2 "Public releases require NOTARY_PROFILE for Developer ID notarization."
  exit 1
fi
# Prefer full Xcode when Command Line Tools is selected; SwiftUI needs its plugins.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p "$ROOT/.build" "$ROOT/build"
LOCK="$ROOT/.build/build.lock"
mkdir "$LOCK" 2>/dev/null || { print -u2 "Another build is active (lock: $LOCK)"; exit 1; }
STAGE=""
PREVIOUS=""
DESTINATION=""
cleanup() {
  if [[ -n "$PREVIOUS" && -d "$PREVIOUS" && ! -e "$DESTINATION" ]]; then
    mv "$PREVIOUS" "$DESTINATION"
  fi
  [[ -z "$STAGE" ]] || rm -rf "$STAGE"
  rmdir "$LOCK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
STAGE="$(mktemp -d "$ROOT/.build/current.XXXXXX")"
SWIFTC="$(xcrun --find swiftc)"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
# ponytail: CLT 27 lacks SwiftUI macros; use its bundled 26.5 SDK until full Xcode is installed.
if [[ -z "${SDKROOT:-}" && "$SWIFTC" == /Library/Developer/CommandLineTools/* && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
  SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
print "Building with SDK: $SDK"
CACHE="$ROOT/.build/module-cache"
APP_NAME="Margin"
[[ "$MODE" != --build-only ]] || APP_NAME="Margin Dev"
APP="$STAGE/$APP_NAME.app"
SPARKLE_VERSION="2.9.6"
SPARKLE_ROOT="$ROOT/.build/sparkle-$SPARKLE_VERSION"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
NAME="Margin-$VERSION-universal.dmg"
OUTPUT="$ROOT/dist/$NAME"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  archive="$ROOT/.build/Sparkle-$SPARKLE_VERSION.zip"
  mkdir -p "$SPARKLE_ROOT"
  curl --fail --location --silent --show-error "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip" -o "$archive"
  print "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606  $archive" | shasum -a 256 -c -
  ditto -x -k "$archive" "$SPARKLE_ROOT"
fi

[[ -x "$SWIFTC" && -d "$SDK" ]] || { print -u2 "A full Xcode installation is required"; exit 1; }

mkdir -p "$CACHE" "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Frameworks" "$STAGE/bin"
sources=("$ROOT"/Sources/**/*.swift(N))
common=(-sdk "$SDK" -swift-version 5 -O -F "${SPARKLE_FRAMEWORK:h}" -framework Sparkle -framework AppKit -framework EventKit -framework UserNotifications -framework SwiftUI -framework Combine -framework CryptoKit -framework Security -framework LocalAuthentication -framework ServiceManagement -framework Carbon -Xlinker -rpath -Xlinker @executable_path/../Frameworks -lsqlite3)

architectures=(arm64 x86_64)
[[ "$MODE" == release ]] || architectures=("$(uname -m)")
for arch in "${architectures[@]}"; do
  CLANG_MODULE_CACHE_PATH="$CACHE" "$SWIFTC" "${common[@]}" -target "$arch-apple-macos13.0" "${sources[@]}" -o "$STAGE/bin/Margin-$arch"
done

lipo -create "$STAGE"/bin/Margin-* -output "$APP/Contents/MacOS/Margin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ "$MODE" == --build-only ]]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.valetivivek.margin.dev' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName Margin Dev' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Margin Dev' "$APP/Contents/Info.plist"
fi
python3 "$ROOT/scripts/package-legal.py" "$APP/Contents/Resources/Legal"
cp -R "$ROOT/Resources/Fonts/." "$APP/Contents/Resources/Fonts/"
cp "$SPARKLE_ROOT/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
"$ROOT/scripts/package-icon.sh" "$APP/Contents/Resources/AppIcon.icns"
if [[ "$MODE" != --build-only ]]; then
  embedded="$APP/Contents/Frameworks/Sparkle.framework"
  signing=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime)
  [[ "$MODE" != release ]] || signing+=(--timestamp)
  codesign "${signing[@]}" "$embedded/Versions/B/XPCServices/Installer.xpc"
  codesign "${signing[@]}" --preserve-metadata=entitlements "$embedded/Versions/B/XPCServices/Downloader.xpc"
  codesign "${signing[@]}" "$embedded/Versions/B/Autoupdate"
  codesign "${signing[@]}" "$embedded/Versions/B/Updater.app"
  codesign "${signing[@]}" "$embedded"
  codesign "${signing[@]}" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
signature="$(codesign -dvvv "$APP" 2>&1)"
if [[ "$MODE" != --build-only && "$signature" == *"Signature=adhoc"* ]]; then
  print -u2 "Production builds cannot use an ad-hoc signature."
  exit 1
fi
if [[ "$MODE" == release && "$signature" != *"Authority=Developer ID Application:"* ]]; then
  print -u2 "Public releases must use a Developer ID Application certificate."
  exit 1
fi
"$APP/Contents/MacOS/Margin" --self-check

# Replace only after compilation, bundle verification and self-check all pass.
publish_app() {
  local candidate="$1"
  DESTINATION="$2"
  PREVIOUS="$STAGE/previous.app"
  [[ ! -e "$DESTINATION" ]] || mv "$DESTINATION" "$PREVIOUS"
  if ! mv "$candidate" "$DESTINATION"; then
    [[ ! -d "$PREVIOUS" ]] || mv "$PREVIOUS" "$DESTINATION"
    return 1
  fi
  rm -rf "$PREVIOUS"
  PREVIOUS=""
}
if [[ "$MODE" == --build-only ]]; then
  CURRENT="$ROOT/build/Margin Dev.app"
else
  mkdir -p "$ROOT/.build/release.noindex"
  CURRENT="$ROOT/.build/release.noindex/Margin.app"
fi
publish_app "$APP" "$CURRENT"
APP="$CURRENT"
print "Verified current app: $APP"
if [[ "$MODE" == --install ]]; then
  if pgrep -x Margin >/dev/null; then
    print -u2 "Quit Margin, then rerun --install. The verified build is ready; the running app was not replaced."
    exit 1
  fi
  ditto "$APP" "$STAGE/install.app"
  publish_app "$STAGE/install.app" /Applications/Margin.app
  print "Installed current app: /Applications/Margin.app"
fi
[[ "$MODE" == release ]] || exit 0

mkdir -p "$ROOT/dist" "$STAGE/dmg"
ditto "$APP" "$STAGE/dmg/Margin.app"
cp "$ROOT/LICENSE" "$STAGE/dmg/LICENSE.txt"
cp "$ROOT/PRIVACY.md" "$ROOT/TERMS.md" "$ROOT/DATA-DELETION.md" "$ROOT/THIRD-PARTY-NOTICES.md" "$ROOT/SECURITY.md" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -ov -format UDZO -volname "Margin $VERSION" -srcfolder "$STAGE/dmg" "$STAGE/$NAME"
hdiutil verify "$STAGE/$NAME"

if [[ "$MODE" == release ]]; then
  notary=(--keychain-profile "$NOTARY_PROFILE" --wait)
  [[ -z "${NOTARY_KEYCHAIN:-}" ]] || notary+=(--keychain "$NOTARY_KEYCHAIN")
  xcrun notarytool submit "$STAGE/$NAME" "${notary[@]}"
  xcrun stapler staple "$STAGE/$NAME"
fi

(cd "$STAGE" && shasum -a 256 "$NAME" > "$NAME.sha256")
mv "$STAGE/$NAME" "$OUTPUT"
mv "$STAGE/$NAME.sha256" "$OUTPUT.sha256"
print "Packaged: $OUTPUT"
