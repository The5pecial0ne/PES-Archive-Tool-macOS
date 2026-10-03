#!/bin/bash
#
# Builds PES Archive Tool for macOS:
#
#   dist/<runtime>/GzsTool        command line tool for .fpk / .fpkd (and .dat, .pftxs, .sbp) archives
#   dist/<runtime>/FoxTool        command line tool for .fox2 files (and the other Fox Engine xml formats)
#   dist/PES Archive Tool.app     a window to drop files onto, with both tools inside
#
#   ./build-macos.sh              build for this Mac (Apple Silicon or Intel)
#   ./build-macos.sh osx-x64      build just the command line tools for the other architecture
#
# Needs the .NET SDK (10 or newer): https://dotnet.microsoft.com/download
# The app additionally needs Xcode's command line tools: xcode-select --install
#
# Everything printed here is also kept in build-macos.log.

set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee build-macos.log) 2>&1

# Match this Mac's processor unless a runtime was asked for explicitly.
case "$(uname -m)" in
  arm64) default_rid="osx-arm64" ;;
  *)     default_rid="osx-x64" ;;
esac
RID="${1:-$default_rid}"
REPO="$PWD"
OUT="dist/$RID"
TOOLS="GzsTool FoxTool"

# The installer puts dotnet in /usr/local/share/dotnet, which isn't always on the PATH.
if ! command -v dotnet >/dev/null 2>&1; then
  for dir in /usr/local/share/dotnet "$HOME/.dotnet" /opt/homebrew/bin; do
    if [ -x "$dir/dotnet" ]; then PATH="$dir:$PATH"; break; fi
  done
fi
if ! command -v dotnet >/dev/null 2>&1; then
  echo "Couldn't find the .NET SDK. Grab it from https://dotnet.microsoft.com/download and run this again."
  exit 1
fi

echo "==> Building the command line tools for $RID with .NET SDK $(dotnet --version)"

# Publishes every tool into the same folder. $1 says whether to bundle the .NET runtime.
publish_tools() {
  local tool
  for tool in $TOOLS; do
    dotnet publish "$tool/$tool.csproj" -c Release -r "$RID" --self-contained "$1" -o "$OUT" --nologo || return 1
  done
}

# First choice: self-contained builds, so the tools run on Macs that have no .NET installed.
# That needs a one-off download of the macOS runtime from nuget.org. If that isn't possible
# (offline, say) we settle for builds that rely on the .NET runtime already on this machine.
rm -rf "$OUT"
if publish_tools true; then
  flavour="self-contained (no .NET install needed to run them)"
else
  echo
  echo "==> Self-contained build didn't work out, building against the installed .NET runtime instead"
  rm -rf "$OUT"
  publish_tools false
  flavour="framework-dependent (they need the .NET runtime that is installed on this Mac)"
fi

GZSTOOL="$REPO/$OUT/GzsTool"
FOXTOOL="$REPO/$OUT/FoxTool"

# Apple Silicon refuses to run unsigned binaries. The SDK normally signs for us; this is the safety net.
for binary in "$GZSTOOL" "$FOXTOOL"; do
  if ! codesign -v "$binary" >/dev/null 2>&1; then
    codesign --force --sign - "$binary"
  fi
done

echo
echo "==> Built: $REPO/$OUT"
echo "    $flavour"
file "$GZSTOOL" "$FOXTOOL" | sed 's/^/    /'

# A build for the other architecture can't be exercised here, so stop at this point.
if [ "$RID" != "$default_rid" ]; then
  echo "==> Skipping the app and the round-trip check ($RID isn't this Mac's architecture)."
  exit 0
fi

# ---------------------------------------------------------------------------------------------
# The drop window: a tiny Swift app with the command line tools tucked inside its bundle.
# ---------------------------------------------------------------------------------------------
APP="dist/PES Archive Tool.app"
app_built="no"
# Without this the app would only open on the macOS version it was built on, or newer.
# macOS 14 is the oldest release the bundled .NET 10 runtime supports, so the app matches that.
# Keep it in step with LSMinimumSystemVersion in macos/GzsToolApp/Info.plist.
MIN_MACOS="14.0"
echo
if command -v swiftc >/dev/null 2>&1; then
  echo "==> Building $APP"
  # The app used to be called GzsTool.app; clear that one out too so only the current one is left.
  rm -rf "$APP" "dist/GzsTool.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  if swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos$MIN_MACOS" \
      macos/GzsToolApp/main.swift -o "$APP/Contents/MacOS/PESArchiveTool"; then
    cp macos/GzsToolApp/Info.plist "$APP/Contents/Info.plist"
    # The app looks for the tools and their dictionaries in its own Resources folder.
    cp "$GZSTOOL" "$FOXTOOL" "$OUT"/*_dictionary.txt "$APP/Contents/Resources/"
    cp macos/GzsToolApp/AppIcon.icns "$APP/Contents/Resources/"
    codesign --force --sign - "$APP"
    # Finder holds on to old icons; a fresh timestamp makes it look again.
    touch "$APP"
    app_built="yes"
    echo "    Built: $REPO/$APP"
  else
    rm -rf "$APP"
    echo "    The app didn't compile (details above). The command line tools are unaffected."
  fi
else
  echo "==> Skipping PES Archive Tool.app: swiftc isn't installed."
  echo "    Run 'xcode-select --install' once, then run this script again."
fi

# ---------------------------------------------------------------------------------------------
# Round-trip check: build small files, take them apart again and compare with the originals.
# This covers the parts the macOS port touched: path separators, zlib, MD5 and text encoding.
# ---------------------------------------------------------------------------------------------
echo
echo "==> Round-trip check"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# cksum prints a checksum and size per file; sorted, that makes a fingerprint of a folder's contents.
fingerprint() {
  find "$1" -type f -exec cksum {} \; | awk '{print $1, $2}' | sort
}

set +e
(
  set -e
  cd "$WORK"

  # --- fpk: file names are stored in the archive, so the folder layout has to survive too ---
  mkdir -p demo_fpk/Assets/demo
  printf 'hello from GzsTool on macOS\n' > demo_fpk/Assets/demo/hello.txt
  cp "$REPO/GzsTool/fpk_dictionary.txt" demo_fpk/Assets/demo/big.txt
  cat > demo.fpk.xml <<'XML'
<?xml version="1.0"?>
<ArchiveFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="FpkFile" Name="demo.fpk" FpkType="Fpk">
  <Entries>
    <Entry FilePath="/Assets/demo/hello.txt" />
    <Entry FilePath="/Assets/demo/big.txt" />
  </Entries>
  <References />
</ArchiveFile>
XML
  "$GZSTOOL" demo.fpk.xml > /dev/null
  mv demo_fpk demo_fpk.original
  "$GZSTOOL" demo.fpk > /dev/null
  diff -r demo_fpk.original demo_fpk
  echo "    fpk          ok"

  # --- dat (qar): both format versions, one plain entry and one zlib-compressed entry each ---
  for version in 1 2; do
    name="demo_v$version"
    mkdir -p "${name}_dat/Assets/demo"
    cp demo_fpk.original/Assets/demo/* "${name}_dat/Assets/demo/"
    cat > "$name.dat.xml" <<XML
<?xml version="1.0"?>
<ArchiveFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="QarFile" Name="$name.dat" Flags="0" Version="$version">
  <Entries>
    <Entry FilePath="/Assets/demo/hello.txt" Compressed="false" Version="$version" />
    <Entry FilePath="/Assets/demo/big.txt" Compressed="true" Version="$version" />
  </Entries>
</ArchiveFile>
XML
    "$GZSTOOL" "$name.dat.xml" > /dev/null
    mv "${name}_dat" "${name}_dat.original"
    "$GZSTOOL" "$name.dat" > /dev/null
    # These made-up paths aren't in the dictionary, so they come back named by their hash.
    # The contents are what matters here.
    [ "$(fingerprint "${name}_dat.original")" = "$(fingerprint "${name}_dat")" ]
    # The compressed entry should really have shrunk the archive.
    [ "$(wc -c < "$name.dat")" -lt "$(wc -c < demo.fpk)" ]
    echo "    dat (qar v$version) ok"
  done

  # --- fox2: xml -> fox2 -> xml -> fox2 has to end with the same bytes it produced the first time ---
  cat > demo.fox2.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<fox formatVersion="2" fileVersion="0" originalVersion="Sat Oct 03 12:00:00 UTC+00:00 2026">
  <classes>
    <class name="Entity" super="" version="2" />
    <class name="Data" super="Entity" version="2" />
    <class name="DemoData" super="Data" version="1" />
  </classes>
  <entities>
    <entity class="DemoData" classVersion="1" addr="0x10000000" unknown1="120" unknown2="0">
      <staticProperties>
        <property name="name" type="String" container="StaticArray" arraySize="1">
          <value>hello from FoxTool on macOS</value>
        </property>
        <property name="count" type="uint32" container="StaticArray" arraySize="1">
          <value>42</value>
        </property>
        <property name="scale" type="float" container="StaticArray" arraySize="1">
          <value>0.1</value>
        </property>
      </staticProperties>
      <dynamicProperties />
    </entity>
  </entities>
</fox>
XML
  "$FOXTOOL" demo.fox2.xml > fox.log
  cp demo.fox2 first.fox2
  rm demo.fox2.xml
  "$FOXTOOL" demo.fox2 >> fox.log
  grep -q "hello from FoxTool on macOS" demo.fox2.xml
  grep -q ">42<" demo.fox2.xml
  grep -q ">0.1<" demo.fox2.xml
  "$FOXTOOL" demo.fox2.xml >> fox.log
  cmp first.fox2 demo.fox2
  echo "    fox2         ok"
)
status=$?
set -e

echo
if [ "$status" -eq 0 ]; then
  echo "==> All good."
  echo "    Command line:  $OUT/GzsTool path/to/file.fpk"
  echo "                   $OUT/FoxTool path/to/file.fox2"
  if [ "$app_built" = "yes" ]; then
    echo "    Drop window:   open \"$APP\""
  fi
else
  if [ -s "$WORK/fox.log" ]; then
    echo "    FoxTool said:"
    sed 's/^/      /' "$WORK/fox.log"
  fi
  echo "==> Everything was built, but the round-trip check failed (see above, also saved in build-macos.log)."
  exit 2
fi
