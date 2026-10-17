# DiskMap

A fast, native macOS disk-usage visualiser. Scan a folder, your home directory or
the whole disk and see every file and folder as a nested, squarified treemap,
sized by how much space it takes up and coloured by file type.

## Features

- **Fast scanning.** Uses `getattrlistbulk` to read a whole directory per syscall,
  and spreads folders across a shared work queue.
- **Nested treemap.** Folders are drawn with their children inside them.
  Double-click to zoom in; press Esc to go up a level.
- **Colour by type.** Images, video, audio, archives, documents, code, binaries,
  disk images and caches each get their own hue.
- **Actions.** Right-click any tile to reveal it in Finder, open it, copy its path
  or move it to the Trash (asks for confirmation first).
- Stays on one volume, skips symlinks, and skips cloud-storage mounts
  (`~/Library/CloudStorage`).

## Requirements

- macOS 13 or later
- Swift 5.9+ (Xcode 15 or the Command Line Tools)

## Build

```sh
./make_app.sh
```

This builds a release binary and wraps it in an ad-hoc signed `DiskMap.app` next
to the script. You can also run it directly with `swift run`.

For complete results when scanning the whole disk, grant the app Full Disk Access
in System Settings → Privacy & Security.

## Project layout

| File | Purpose |
| --- | --- |
| `Scanner.swift` | Multithreaded `getattrlistbulk` scanner |
| `Node.swift` | File/folder tree model |
| `Treemap.swift` | Squarified layout (Bruls et al.) and colour palette |
| `Model.swift` | App state, navigation and file actions |
| `ContentView.swift` | SwiftUI interface and Canvas rendering |
