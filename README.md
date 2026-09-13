# myserves

A command-line tool for managing the macOS **"Connect to Server" (⌘K) favourites** —
the starred server list in Finder's *Connect to Server* dialog.

```sh
myserves add smb://nas.example.com/media "Media"
myserves list
myserves remove "Media"
```

## Why this exists

Plenty of tools manage the **Finder sidebar** favourites
([mysides](https://github.com/mosen/mysides),
[sidebar-editor](https://github.com/fabienconus/sidebar-editor),
[7onnie/mysides](https://github.com/7onnie/mysides)) — but they all target the
`FavoriteItems` list. Nothing maintained manages the **Connect to Server**
favourites, which are a *separate* shared file list: `FavoriteServers`. The one
project that ever targeted it
([robperc/FavServersEditor](https://github.com/robperc/FavServersEditor)) used the
`com.apple.sidebarlists` preferences API that Apple stopped honouring after
OS X 10.12.

`myserves` fills that gap, and does it without requiring Full Disk Access.

## Requirements

- macOS 13 (Ventura) or later — tested on macOS 26 (Tahoe)
- Apple Silicon or Intel
- No Full Disk Access, no `sudo`

## Install

### Build from source

Requires the Swift toolchain (Xcode or the Command Line Tools: `xcode-select --install`).

```sh
git clone https://github.com/YOURNAME/myserves.git
cd myserves
swift build -c release
cp .build/release/myserves /usr/local/bin/
```

### Prebuilt binary

If you download a release binary, macOS Gatekeeper quarantines it. Clear the flag:

```sh
xattr -d com.apple.quarantine ./myserves
```

## Usage

```
myserves list [--json]            List favourite servers
myserves add <url> [name]         Add a favourite (name optional)
      [--force]                   Add even if the URL already exists
myserves remove <name-or-url>     Remove favourites matching a name or URL
myserves version                  Print version
myserves help                     Show help
```

### List

```sh
$ myserves list
smb://nas.example.com
Media -> smb://nas.example.com/media
nfs://10.0.0.5/export

$ myserves list --json
[{"name":"smb://nas.example.com","url":"smb://nas.example.com"}, ...]
```

Entries whose display name equals their URL print as just the URL; entries with a
custom name print as `name -> url`.

### Add

```sh
# URL only — Finder derives the display name
myserves add smb://nas.example.com

# URL plus a friendly display name (shown in ⌘K)
myserves add smb://nas.example.com/media "Media"

# Other schemes work too
myserves add afp://timecapsule.local
myserves add nfs://10.0.0.5/export "Backups"
```

The URL comes **first**, the optional name second. Duplicate URLs are refused
unless you pass `--force`. `file://` paths are rejected — those belong in the
Finder sidebar (use a sidebar tool for that).

### Remove

```sh
myserves remove "Media"                          # by display name
myserves remove smb://nas.example.com/media      # by URL
```

Removes every favourite matching the given name or URL.

## How it works

The favourites live in an `NSKeyedArchiver` blob at:

```
~/Library/Application Support/com.apple.sharedfilelist/
    com.apple.LSSharedFileList.FavoriteServers.sfl3
```

(`.sfl2` before Ventura, `.sfl4` on macOS 26+.) That directory is TCC-protected —
a normal process reading it directly gets `Operation not permitted` unless it has
Full Disk Access.

`myserves` never touches the file. The authoritative copy of the list is held by
the **`sharedfilelistd`** daemon, and the `LSSharedFileList` C functions are thin
clients that talk to it over XPC. Because the daemon already holds the necessary
entitlement, every read and write goes through it — **no Full Disk Access
required**, and Finder's ⌘K dialog reflects changes immediately.

`LSSharedFileList` was removed from Apple's *public headers* years ago, but the
implementation — including a first-class `kLSSharedFileListFavoriteServers`
symbol — is still present and functional in CoreServices (confirmed on
macOS 26). `myserves` loads the symbols at runtime with `dlopen`/`dlsym` and uses
`LSSharedFileListCreate` with the `FavoriteServers` list identifier.

## Acknowledgements

The runtime `dlopen`/`dlsym` approach and the `kLSSharedFileListItemLast`
sentinel handling are adapted from [7onnie/mysides](https://github.com/7onnie/mysides)
(MIT), itself a rewrite of the original [mosen/mysides](https://github.com/mosen/mysides)
(MIT) by Eamon Brosnan. Those tools manage the Finder *sidebar*; `myserves`
applies the same technique to the *Connect to Server* favourites.

## License

MIT — see [LICENSE](LICENSE).
