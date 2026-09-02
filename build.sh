#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
CACHE="$ROOT/.build/module-cache"
APP="$ROOT/build/Margin.app"

[[ -x "$SWIFTC" && -d "$SDK" ]] || { print -u2 "A full Xcode installation is required"; exit 1; }

rm -rf "$APP"
mkdir -p "$CACHE" "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts" "$ROOT/.build/bin"
sources=("$ROOT"/Sources/**/*.swift(N))
common=(-sdk "$SDK" -swift-version 5 -O -framework AppKit -framework SwiftUI -framework Combine -framework CryptoKit -framework Security -framework LocalAuthentication -framework ServiceManagement -framework Carbon -lsqlite3)

for arch in arm64 x86_64; do
  CLANG_MODULE_CACHE_PATH="$CACHE" "$SWIFTC" "${common[@]}" -target "$arch-apple-macos13.0" "${sources[@]}" -o "$ROOT/.build/bin/Margin-$arch"
done

lipo -create "$ROOT/.build/bin/Margin-arm64" "$ROOT/.build/bin/Margin-x86_64" -output "$APP/Contents/MacOS/Margin"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/Fonts/." "$APP/Contents/Resources/Fonts/"
[[ ! -f "$ROOT/Resources/AppIcon.icns" ]] || cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Margin" --self-check
print "Built: $APP"
