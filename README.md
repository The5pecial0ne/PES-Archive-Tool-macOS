# PES Archive Tool

Unpack and repack Pro Evolution Soccer (Fox Engine) files on a Mac, natively. No Wine, no CrossOver.

It comes in two forms that do the same work:

* **PES Archive Tool.app**, a small window you drop files onto.
* **GzsTool** and **FoxTool**, the command line tools the app runs behind the scenes.

This is a macOS port of two Windows tools by [Atvaark](https://github.com/Atvaark),
[GzsTool](https://github.com/Atvaark/GzsTool) and [FoxTool](https://github.com/Atvaark/FoxTool),
with a drop window added on top. See [Credits and licence](#credits-and-licence).

It is a fan-made modding utility. It is not affiliated with or endorsed by Konami, and it is a separate
project from the Windows program "PES Archive Tools".

## What it does

| Drop this | You get | Done by |
| --- | --- | --- |
| `stadium.fpk` or `stadium.fpkd` | a folder `stadium_fpk` / `stadium_fpkd` with the contents, plus `stadium.fpk.xml` | GzsTool |
| `stadium.fpk.xml` or `stadium.fpkd.xml` | the archive, rebuilt from that folder | GzsTool |
| `scene.fox2` | `scene.fox2.xml`, the same data as readable xml | FoxTool |
| `scene.fox2.xml` | `scene.fox2`, rebuilt from the xml | FoxTool |
| a folder | every `.fpk` and `.fpkd` inside it unpacked, however deep | GzsTool |

Everything is written next to the file you dropped.

Two rules worth knowing:

* **Repacking overwrites.** The rebuilt `.fpk`, `.fpkd` or `.fox2` replaces the file of the same name.
  Keep a copy of the original if you may want it back.
* **Repacking only happens for an xml file you drop yourself.** Xml files inside a dropped folder are
  left alone, so dropping a folder can never overwrite an archive.
* **`.fox2` files are only converted when you drop them yourself.** Unpacked archives often contain
  `.fox2` files; they stay untouched until you drag one onto the window.

A typical round: drop `stadium.fpkd` to unpack it, drop a `.fox2` from the unpacked folder if you need
to edit it, edit the xml, drop the `.fox2.xml` to rebuild the `.fox2`, then drop `stadium.fpkd.xml` to
rebuild the archive.

## Install

### Download (Apple Silicon Macs)

You need an Apple Silicon Mac (M1 or newer) running macOS 14 or newer.

1. Download `PES-Archive-Tool-macOS-arm64.zip` from the
   [latest release](https://github.com/The5pecial0ne/PES-Archive-Tool-macOS/releases/latest) and unzip it.
2. Move `PES Archive Tool.app` to your Applications folder.
3. Allow it to run. The app is not signed with an Apple developer certificate, so macOS blocks a
   downloaded copy the first time. Either run this once in Terminal:

   ```
   xattr -dr com.apple.quarantine "/Applications/PES Archive Tool.app"
   ```

   or try to open the app, then go to System Settings → Privacy & Security and choose "Open Anyway".

Nothing else needs installing; the app carries everything it needs.

If you only want the command line tools, the same release has `PES-Archive-Tool-cli-macOS-arm64.zip`
with `GzsTool`, `FoxTool` and their dictionary files. Keep them together in one folder and clear the
download flag the same way: `xattr -dr com.apple.quarantine path/to/the/folder`.

The downloads are built for Apple Silicon. On an Intel Mac, build from source.

macOS 14 is the oldest version the .NET 10 runtime inside the tools supports. Releases are built and
tested on macOS 27; older versions back to 14 should work but have not been tried.

### Build from source

You need:

* the [.NET SDK](https://dotnet.microsoft.com/download), version 10 or newer
* Xcode's command line tools for the app: `xcode-select --install`

Then:

```
git clone https://github.com/The5pecial0ne/PES-Archive-Tool-macOS.git
cd PES-Archive-Tool-macOS
./build-macos.sh
```

The script builds everything, runs a pack/unpack round trip to make sure the result behaves, and leaves:

```
dist/PES Archive Tool.app       the drop window, with both tools inside it
dist/osx-arm64/GzsTool          command line tools (dist/osx-x64 on Intel Macs)
dist/osx-arm64/FoxTool
dist/osx-arm64/*_dictionary.txt name lists the tools read at startup
```

The app can be moved anywhere, `/Applications` for example. The command line tools need their
`*_dictionary.txt` files to stay in the same folder as the executables.

Without Xcode's command line tools the script still builds GzsTool and FoxTool and skips the app.
An app you build yourself runs straight away, without the extra step from the download instructions.

## Using the app

Open `PES Archive Tool.app` and drop files or folders onto the window. Clicking the drop area opens a
file picker instead, and dropping onto the app's Dock icon works too.

The list under the drop area shows one line per file: what it was turned into, or what went wrong.
"Show in Finder when done" reveals the results after each drop.

The first time you drop something from Desktop, Documents or Downloads, macOS asks whether the app may
access that folder.

## Using the command line

Both tools take a single path and work out from its name what to do.

```
GzsTool stadium.fpk          # unpack  -> stadium_fpk/ and stadium.fpk.xml
GzsTool stadium.fpk.xml      # repack  -> stadium.fpk
GzsTool some_folder          # unpack every .fpk and .fpkd in the folder

FoxTool scene.fox2           # unpack  -> scene.fox2.xml
FoxTool scene.fox2.xml       # repack  -> scene.fox2
FoxTool some_folder          # unpack every file FoxTool understands in the folder
```

The command line tools cover more formats than the app's window does:

* GzsTool also handles `.dat` (qar), `.pftxs` and `.sbp` archives, the same way as `.fpk`.
* FoxTool also handles `.bnd`, `.clo`, `.des`, `.evf`, `.fsd`, `.lad`, `.parts`, `.ph`, `.phsd`, `.sdf`,
  `.sim`, `.tgt`, `.vdp`, `.veh` and `.vfxlf`, the same way as `.fox2`.

Remarks carried over from the original GzsTool:

* Repacking a `.dat` file without changes gives a smaller file. Formerly encrypted entries are not
  encrypted again, so their keys no longer need storing.
* Ground Zeroes `g0s` and `pftxs` files need the original [GzsTool v0.2](https://github.com/Atvaark/GzsTool/releases/tag/v0.2).

## What is in this repository

```
GzsTool/         command line front end for archives, plus its two dictionaries
GzsTool.Core/    the archive formats: fpk, qar (dat), pftxs, sbp
FoxTool/         compiler and decompiler for fox2 and the other Fox Engine xml formats, plus its dictionary
CityHash/        the hash function both tools use for names (CityHash 1.0.3)
macos/           the app: one Swift file, its Info.plist, the icon and the script that draws it
build-macos.sh   builds all of the above and checks the result
make-release-zips.sh  zips a finished build into the two files attached to a release
PesArchiveTool.slnx   solution file, for opening all four .NET projects at once in an IDE
```

## What changed compared to the originals

The file formats, hashing and encryption code are Atvaark's and are untouched. The port is about
everything around them:

* Both tools target modern .NET (10) instead of the Windows-only .NET Framework 4.5.
* No NuGet packages are needed. zlib comes from the .NET runtime, and CityHash, which used to be the
  `CityHash.Net.Legacy` package, is included as source from [Atvaark/cityhash](https://github.com/Atvaark/cityhash).
* Paths inside archives and xml files keep their Windows backslashes. They are translated to the local
  separator only when touching the disk, so xml files stay interchangeable with the Windows tools.
* Text is read as Latin-1, which is what the old Windows default code page amounted to. Modern .NET
  defaults to UTF-8, which would mangle the raw bytes in encrypted fpk names.
* The dictionaries are found next to the executable even in a single-file build.
* Repacking writes to a temporary file first and swaps it in when complete, so a failed repack leaves
  the existing file as it was.
* FoxTool reports failure through its exit code, so scripts and the app can tell when a file did not convert.
* File extensions are matched without regard to case.

The projects are plain .NET, so `dotnet publish GzsTool/GzsTool.csproj -c Release -r win-x64` (or
`linux-x64`) should produce builds for other systems. Only macOS has been built and tested here.

## Credits and licence

* GzsTool and FoxTool, and the managed CityHash port: © Atvaark, MIT licence.
  FoxTool was taken at version 0.2.6.0, GzsTool at version 0.6.0.
* CityHash itself: © Google, MIT licence (see `CityHash/LICENSE`).
* macOS port, build script and app: MIT licence.

The full licence text is in [LICENSE](LICENSE). "Pro Evolution Soccer", "PES" and "Fox Engine" are
trademarks of Konami; they are used here only to say which files the tool reads.
