#!/bin/sh
#
# build.sh -- builds Organizer.app from the Swift package and bundles the
# scripts from the repo root into it.
#
#   app/build.sh              # release build -> app/dist/Organizer.app
#   app/build.sh debug        # debug build
#   open app/dist/Organizer.app
#
# No Xcode project: `swift build` produces the executable and this script lays
# out the bundle (Info.plist, binary, Resources/scripts). The app is ad-hoc
# signed so macOS keeps the Automation permission across launches.
#
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
config=${1:-release}
app="$here/dist/Organizer.app"

swift build --package-path "$here" -c "$config"
bin="$(swift build --package-path "$here" -c "$config" --show-bin-path)/Organizer"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/scripts"
cp "$bin" "$app/Contents/MacOS/Organizer"
cp "$repo"/*.applescript "$app/Contents/Resources/scripts/"
sed "s|@REPO_ROOT@|$repo|" "$here/Info.plist" > "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force --sign - "$app" >/dev/null 2>&1

echo "Built $app"
