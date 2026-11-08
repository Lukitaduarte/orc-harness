#!/usr/bin/env bash
# Builds the macOS release: Orc Harness.app with orcd and its helpers inside
# (Contents/Resources/bin), as a dmg and a zip, plus an orcd-only tarball.
# Usage: scripts/package-macos.sh VERSION [BUILD_NUMBER]
set -euo pipefail
version="${1:?usage: $0 VERSION [BUILD_NUMBER]}"
build="${2:-1}"
cd "$(dirname "$0")/.."
root="$PWD"
dist="$root/dist"
rm -rf "$dist" && mkdir -p "$dist"
bins=(orcd orc-statusline orc-commit-check orc-mcp orc-hook)

# 1. The daemon, universal (Apple silicon + Intel).
# `orcd version` reports it; the app compares it to update its daemon.
export ORC_VERSION="$version"
for t in aarch64-apple-darwin x86_64-apple-darwin; do
  cargo build --release --locked --bins --target "$t"
done
daemon="$dist/orcd-$version-macos-universal"
mkdir -p "$daemon"
for b in "${bins[@]}"; do
  lipo -create -output "$daemon/$b" \
    "target/aarch64-apple-darwin/release/$b" "target/x86_64-apple-darwin/release/$b"
  codesign --force --sign - "$daemon/$b"
done
cp LICENSE "$daemon/"
tar -C "$dist" -czf "$daemon.tar.gz" "$(basename "$daemon")"

# 2. The app, with the daemon inside (it installs and pairs with it on
#    first launch).
(cd app && flutter build macos --release --build-name "$version" --build-number "$build")
app="$root/app/build/macos/Build/Products/Release/Orc Harness.app"
mkdir -p "$app/Contents/Resources/bin"
cp "$daemon"/orc* "$app/Contents/Resources/bin/"
# Ad-hoc signature over the new contents, keeping the app's entitlements.
codesign --force --sign - --preserve-metadata=entitlements,flags,runtime "$app"
codesign --verify --strict "$app"

# 3. dmg (drag to Applications) and zip.
name="OrcHarness-$version-macos"
ditto -c -k --keepParent "$app" "$dist/$name.zip"
stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Orc Harness" -srcfolder "$stage" -ov -format UDZO "$dist/$name.dmg" >/dev/null
rm -rf "$stage"
(cd "$dist" && shasum -a 256 ./*.dmg ./*.zip ./*.tar.gz | sed 's| \./| |' > SHA256SUMS.txt)
cat "$dist/SHA256SUMS.txt"
