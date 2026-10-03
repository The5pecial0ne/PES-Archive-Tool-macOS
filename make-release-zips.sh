#!/bin/bash
#
# Zips a finished build into the two files that get attached to a GitHub release:
#
#   dist/PES-Archive-Tool-macOS-<arch>.zip       the app
#   dist/PES-Archive-Tool-cli-macOS-<arch>.zip   GzsTool, FoxTool and their dictionaries
#
# Run ./build-macos.sh first, then this.

set -euo pipefail
cd "$(dirname "$0")"

case "$(uname -m)" in
  arm64) arch="arm64"; rid="osx-arm64" ;;
  *)     arch="x64";   rid="osx-x64" ;;
esac

APP="dist/PES Archive Tool.app"
CLI="dist/$rid"

if [ ! -d "$APP" ] || [ ! -x "$CLI/GzsTool" ] || [ ! -x "$CLI/FoxTool" ]; then
  echo "There is no finished build in dist/ yet. Run ./build-macos.sh first."
  exit 1
fi

app_zip="dist/PES-Archive-Tool-macOS-$arch.zip"
cli_zip="dist/PES-Archive-Tool-cli-macOS-$arch.zip"
rm -f "$app_zip" "$cli_zip"

# ditto is the macOS way to zip an app: it keeps the permissions and signature intact.
ditto -c -k --keepParent "$APP" "$app_zip"
# No --keepParent here, so the tools and dictionaries sit at the top of the zip.
ditto -c -k "$CLI" "$cli_zip"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "Zipped version $version:"
ls -lh "$app_zip" "$cli_zip" | awk '{print "  " $5 "  " $NF}'
echo
echo "Checksums (SHA-256), for the release notes:"
(cd dist && shasum -a 256 "$(basename "$app_zip")" "$(basename "$cli_zip")")
