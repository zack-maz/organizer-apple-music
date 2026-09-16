# organizer-apple-music

Turns a messy Apple Music library into a tidy one: every song filed into a
playlist for its genre, and those playlists grouped into a handful of folders
like `hip-hop & rap`, `rock & alternative` and `electronic & dance`.

It is a set of small AppleScript files that talk to the Music app on your Mac.
They only create and remove **playlists** — your songs themselves are never
moved, edited, or deleted.

## What you need

- A Mac with the Music app.
- Permission for Terminal to control Music. The first time you run a script,
  macOS asks; say yes. (If you said no, turn it on under
  **System Settings → Privacy & Security → Automation**.)

## Getting started

Open Terminal in this folder and run these in order:

```sh
./backup-playlists.applescript          # 1. save a copy of your playlists first
./build-genres.applescript --dry-run    # 2. preview what will be created
./build-genres.applescript --replace    # 3. build the genre folders and playlists
./mark-unavailable.applescript          # 4. set aside songs that can never download
```

Every script accepts `--help`, and most accept `--dry-run` to show what they
*would* do without changing anything. When in doubt, dry-run first.

## Keeping it up to date

Added new music? Check what isn't filed yet, then rebuild:

```sh
./whats-new.applescript                 # songs not yet in any genre playlist
./build-genres.applescript              # file just the new songs
./build-genres.applescript --replace    # or: rebuild everything from scratch
```

Without `--replace`, the build script leaves your existing playlists alone and
only adds the new songs — creating a playlist (and parent folder) for any genre
that doesn't have one yet. Rebuild with `--replace` now and then; it also cleans
up the duplicate playlist entries that iCloud sync tends to create over time.

## Everything else

| Script | What it does |
| --- | --- |
| `whats-new` | Lists songs that aren't in any genre playlist yet. |
| `dedupe-playlists` | Removes repeated songs within the genre playlists. |
| `backup-playlists` | Saves your playlists to files on disk. |
| `restore-playlists` | Recreates playlists from a backup. |

The download scripts (`download-report`, `download-genres`,
`watch-downloads`) are still in the repo but **not supported**: queued
downloads can stall indefinitely with no way to see why or fix it from a
script. Download songs from the Music app itself. They are disabled in the app.

## Good to know

- **Deleting a playlist is permanent** and syncs to all your devices. Back up
  before any rebuild.
- **Rebuild rather than edit.** iCloud tends to undo renames and moves made to
  existing playlists, but leaves newly created ones alone — which is why the
  build script creates everything in its final form in one go.

## App

There is also a small native macOS app that fronts the same scripts: the
library numbers at a glance, one row per script, and a console that streams
the output. Anything that changes the library runs its dry run first and only
then offers a **Run for real** button.

```sh
app/build.sh                    # builds app/dist/Organizer.app (needs Xcode)
open app/dist/Organizer.app
```

The first run asks for permission to control Music, the same as Terminal did.
The app bundles a copy of the scripts; to pick up edits without rebuilding,
point it at this folder with **Change** under *scripts* at the bottom of the
window. `cd app && swift test` runs the unit tests.

## More detail

- [SCRIPTS.md](SCRIPTS.md) — every script and option, the cautions in full, and
  notes for anyone editing the scripts.
- [STATE.md](STATE.md) — where this library currently stands.
