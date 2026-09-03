#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
CACHE="$ROOT/.build/module-cache"
APP="$ROOT/build/Margin.app"
SPARKLE_VERSION="2.9.6"
SPARKLE_ROOT="$ROOT/.build/sparkle-$SPARKLE_VERSION"
SPARKLE_FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  archive="$ROOT/.build/Sparkle-$SPARKLE_VERSION.zip"
  mkdir -p "$SPARKLE_ROOT"
  curl --fail --location --silent --show-error "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-for-Swift-Package-Manager.zip" -o "$archive"
  print "8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606  $archive" | shasum -a 256 -c -
  ditto -x -k "$archive" "$SPARKLE_ROOT"
fi

[[ -x "$SWIFTC" && -d "$SDK" ]] || { print -u2 "A full Xcode installation is required"; exit 1; }

rm -rf "$APP"
mkdir -p "$CACHE" "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$APP/Contents/Frameworks" "$ROOT/.build/bin"
sources=("$ROOT"/Sources/**/*.swift(N))
common=(-sdk "$SDK" -swift-version 5 -O -F "${SPARKLE_FRAMEWORK:h}" -framework Sparkle -framework AppKit -framework SwiftUI -framework Combine -framework CryptoKit -framework Security -framework LocalAuthentication -framework ServiceManagement -framework Carbon -Xlinker -rpath -Xlinker @executable_path/../Frameworks -lsqlite3)

for arch in arm64 x86_64; do
  CLANG_MODULE_CACHE_PATH="$CACHE" "$SWIFTC" "${common[@]}" -target "$arch-apple-macos13.0" "${sources[@]}" -o "$ROOT/.build/bin/Margin-$arch"
done

lipo -create "$ROOT/.build/bin/Margin-arm64" "$ROOT/.build/bin/Margin-x86_64" -output "$APP/Contents/MacOS/Margin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/Fonts/." "$APP/Contents/Resources/Fonts/"
cp "$SPARKLE_ROOT/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
[[ ! -f "$ROOT/Resources/AppIcon.icns" ]] || cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  embedded="$APP/Contents/Frameworks/Sparkle.framework"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime "$embedded/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime --preserve-metadata=entitlements "$embedded/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime "$embedded/Versions/B/Autoupdate"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime "$embedded/Versions/B/Updater.app"
  codesign --force --sign "$CODE_SIGN_IDENTITY" --options runtime "$embedded"
  codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Margin" --self-check
print "Built: $APP"
