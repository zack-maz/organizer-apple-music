# organizer-apple-music

AppleScript tools that reorganize an Apple Music library from the command line:
one playlist per genre, grouped into parent folders, with a backup/restore pair
so nothing is lost along the way.

All four scripts drive `Music.app` directly through AppleScript. Nothing touches
audio files, and no track is ever moved or deleted — only playlists are created,
moved, and removed.

## Requirements

- macOS with Music.app (built and tested on macOS 26.5)
- Terminal must be allowed to control Music under
  **System Settings → Privacy & Security → Automation**. The first run triggers
  the prompt; denying it makes every script fail with a `-1743` error.

Each script has a `#!/usr/bin/osascript` shebang, so run it directly or via
`osascript <file>`. Pass `--help` to any of them.

## Scripts


### `build-genres.applescript` — build everything, in one pass

**This is the script to use.** It creates the genre folder, the 13 parent
folders, and all 84 playlists — each made *directly inside* its parent folder,
already lowercase, then filled.

```sh
./build-genres.applescript --dry-run     # preview the whole plan
./build-genres.applescript --replace     # build it (deletes any existing folder first)
```

| Option | Meaning |
| --- | --- |
| `--dry-run` | Print the full plan and any unmapped genres; create nothing. |
| `--replace` | Delete an existing folder of the same name first. Required if one exists. |
| `--folder NAME` | Folder to create (default `genres`). |
| `--min-tracks N` | Skip genres with fewer than N tracks (default 1). |

**Why one pass.** iCloud sync reverts *modifications* to already-synced objects
while letting *creations* stand — new objects carry new IDs and cannot conflict.
The old three-step pipeline created flat title-case playlists and then moved and
renamed them, and sync undid both, repeatedly. Building the final shape up front
leaves nothing to revert. See Cautions.

Genres are folded to lowercase *before* uniquing, so `Hip-Hop` and `hip-hop`
become one `hip-hop` playlist instead of two competing ones. Nothing is merged
beyond case — `hip-hop`, `rap` and `hip-hop/rap` stay separate playlists sharing
a parent. Edit the `groups` table at the top to change the taxonomy; a genre not
in the table is created at the top of `genres` and reported under `UNMAPPED`.

Tracks with no genre are shown as `unknown genre` but must be *filtered* on the
empty string — no track carries the placeholder as its actual genre.

### `whats-new.applescript` — find songs added since the last rebuild

```sh
./whats-new.applescript              # what is in the library but not filed
./whats-new.applescript --days 30    # also: everything added in the last 30 days
./whats-new.applescript --all        # do not cap the lists at 40 entries
```

This compares the library against the genre tree directly: any track not present
in any genre playlist was added after the last rebuild. That is exact, not a
heuristic, and it is the reliable answer to "what still needs organizing".

It deliberately does **not** use download state. `downloaded` is unreadable on
subscription tracks, and the `no longer available` tracks never download, so
"not downloaded" cannot distinguish new songs from permanently-stuck ones.

### `download-report.applescript` — download coverage (read-only)

```sh
./download-report.applescript
```

Reports how much of each genre playlist is downloaded, and totals. **It contains
no `download` command and cannot start a download**, by construction — queuing
lives in a separate file so that asking "what is downloaded?" can never begin
downloading anything.

Presence of `location` is the proxy for download state, since Music exposes no
readable `downloaded` property on subscription tracks. That is one Apple event
per track, so a full pass takes several minutes.

### `download-genres.applescript` — download coverage, and queue the gaps

Walks the genre playlists, reports how many of each one's tracks already have a
local file, and queues the rest for download.

```sh
./download-genres.applescript --dry-run   # coverage report only, queue nothing
./download-genres.applescript             # report, then queue the gaps
```

Music exposes no readable "is this downloaded" property on subscription tracks
(`downloaded` errors, and `whose downloaded is false` is unsupported), so this
uses presence of `location` as the proxy — it raises an error when a track has
no local file. That means one Apple event per track, so a full pass over a few
thousand tracks takes several minutes.

`download` only queues. It returns immediately and Music works through the queue
in the background over hours. Re-run with `--dry-run` any time to see progress.
Tracks with cloud status `no longer available` are counted separately, since
they can never download.

### `mark-unavailable.applescript` — collect the tracks that can never download

Gathers every track with cloud status `no longer available` (pulled from the
Apple Music catalogue) into one playlist, `wont download`.

```sh
./mark-unavailable.applescript --dry-run
./mark-unavailable.applescript
```

These tracks stay in your library but can never download, so without this they
read as permanently un-downloaded and look like new, unfiled songs. The playlist
is created at the **top level**, deliberately outside `genres`, so
`organize-by-genre --replace` does not delete it along with the folder. Re-run it
whenever you want the list refreshed — it deletes and recreates the playlist
rather than editing rows, for the sync reason described under Cautions.

### `dedupe-playlists.applescript` — remove duplicate entries

Removes repeated tracks from the playlists in the genre folder, keeping the
first occurrence.

```sh
./dedupe-playlists.applescript --dry-run
./dedupe-playlists.applescript
```

Only playlist membership changes: removing a row never removes the track from
your library, and the script reports the library count before and after so you
can confirm that. Reach for this if a playlist's track total ever exceeds the
number of distinct songs in it — see the caution below.

### `backup-playlists.applescript` — save playlists to disk

Writes one TSV per playlist (`persistentID`, `title`, `artist`, `album`) plus a
`MANIFEST.tsv` listing every playlist and its track count.

```sh
./backup-playlists.applescript                  # -> backups/playlists-YYYYMMDD-HHMMSS
./backup-playlists.applescript /some/other/dir
```

It captures playlists at the **top level** of the library — the genre playlists
inside `genres` are skipped, since they are regenerable from the library itself.

### `restore-playlists.applescript` — bring them back

Recreates playlists from a backup directory, matching tracks by persistent ID.

```sh
./restore-playlists.applescript backups/playlists-20260905-141540
./restore-playlists.applescript backups/playlists-20260905-141540 "Road Trip" "Focus"
```

With no playlist names it restores everything in the directory except Apple's
built-in smart playlists (`Music`, `Music Videos`, `Favorite Songs`), which Music
manages itself.

Restore only recovers songs **still in your library**. A track removed from the
library since the backup will not come back, and the playlist is recreated
without it.

### Superseded scripts

These were the original three-step pipeline: `organize-by-genre` built flat
title-case playlists, `group-genres` moved them into parent folders, and
`lowercase-names` renamed them. They work, but those move and rename steps are
exactly what iCloud sync kept reverting — see Cautions. Use
`build-genres.applescript` to build from scratch; reach for these only to
reorganize an existing folder in place.

### `organize-by-genre.applescript` — build the genre playlists

Reads every track's genre and creates one playlist per distinct genre inside a
folder (default name: `genres`).

```sh
./organize-by-genre.applescript --dry-run     # preview counts, change nothing
./organize-by-genre.applescript               # build it
./organize-by-genre.applescript --replace     # delete the folder and rebuild
```

| Option | Meaning |
| --- | --- |
| `--dry-run` | Print each genre and its track count; create nothing. |
| `--replace` | Delete an existing folder of the same name first. Without it, an existing folder is an error. |
| `--folder NAME` | Folder to create (default `genres`). |
| `--min-tracks N` | Skip genres with fewer than N tracks (default 1). Those tracks end up in no playlist. |
| `--unknown NAME` | Playlist name for tracks with no genre (default `Unknown Genre`). |

Genres are used exactly as Apple tags them — nothing is merged or normalized, so
`Hip-Hop/Rap`, `Hip-Hop`, `Rap` and `UK Hip-Hop` stay four separate playlists.

**Re-running is not incremental.** It only creates. After adding music, rerun
with `--replace`, which rebuilds from scratch and discards any manual edits you
made inside those playlists (and the parent folders — see below).

### `group-genres.applescript` — sort the genre playlists into parent folders

Moves each genre playlist into a broader parent folder inside `genres`. Still no
merging: a genre keeps its own playlist, it just gains a parent.

```sh
./group-genres.applescript --dry-run    # preview, and list unmapped genres
./group-genres.applescript              # apply
./group-genres.applescript --flatten    # undo: move all back up, delete parents
```

The taxonomy is the `groups` table at the top of the file — edit it and re-run.
The script is idempotent and reuses folders that already exist. A genre not named
in the table is left at the top level of `genres` and reported under `UNMAPPED`,
so new genres are surfaced rather than silently filed.

Default grouping (13 folders): Hip-Hop & Rap, Rock & Alternative,
Electronic & Dance, Pop, R&B Soul & Funk, Jazz & Blues,
Folk Country & Songwriter, Reggae & Caribbean, Latin & Brazilian,
Global & World, Ambient & Instrumental, Soundtracks & Screen, Other.

Run this **after** any `organize-by-genre.applescript --replace`, which removes
the parent folders along with the rest of the folder.

### `lowercase-names.applescript` — lowercase the folder and playlist names

Lowercases the genre folder, its parent folders, and every playlist inside it.
Track metadata is never touched.

```sh
./lowercase-names.applescript --dry-run
./lowercase-names.applescript
```

Folding uses Foundation's `lowercaseString`, so non-ASCII names come out right
(`Música Mexicana` → `música mexicana`); `tr` would mangle them. It reports name
collisions before renaming — note that the parent folder `Pop` and the genre
playlist `Pop` both fold to `pop`, which Music permits because folders and
playlists are separate collections.

## Typical run

```sh
./backup-playlists.applescript             # safety net first
./build-genres.applescript --dry-run       # preview folders + playlists
./build-genres.applescript --replace       # build it all in final form
./mark-unavailable.applescript             # collect never-downloadable tracks
```

Then verify — all three properties, not just track counts, because nesting and
casing are what iCloud sync attacks:

```sh
./whats-new.applescript                    # confirms every track is filed
./dedupe-playlists.applescript --dry-run   # confirms no duplicate entries
```

`build-genres.applescript` replaces the original three-step pipeline
(`organize-by-genre` → `group-genres` → `lowercase-names`). Those still work and
are documented above, but their move and rename steps are precisely what sync
kept undoing, so reach for them only to reorganize an existing folder in place.

## Cautions

- **Playlist deletion is permanent.** Music has no trash or undo for playlists,
  and the deletion syncs to iCloud and your other devices. Take a backup before
  anything that removes playlists, and keep `backups/` somewhere safe.
- **Verify, don't trust the success line.** These scripts report what they
  actually found in Music afterward; when writing your own, check the resulting
  playlist and track counts rather than the "done" message.
- **Create; never modify.** The central lesson. iCloud Music Library reverts
  local *modifications* to synced objects while letting *creations* stand.
  Confirmed four times: deleting duplicate rows, renaming 97 playlists to
  lowercase, and moving 84 playlists into parent folders were all undone —
  exactly the edited objects reverted, untouched ones survived, and track
  membership (which came from creation) held every time.
  `build-genres.applescript` issues no `move` and no rename, which is why it
  holds. Verify **nesting and casing**, not just track counts.
- **Playlist membership duplicates itself over time, and regenerating is the
  fix.** Observed twice: contents appended three times, and later doubled again
  eight days after a clean build during which no script edited a single row.
  Distinct track IDs stayed correct both times, so nothing is lost — only
  duplicate membership rows accumulate. It was first assumed to be a conflict
  with local row edits; that was wrong, since it recurs with no edits at all.
  Re-run `./build-genres.applescript --replace` periodically. Check with
  `./dedupe-playlists.applescript --dry-run`, which compares rows to distinct IDs.
- **Rebuild, don't repair.** During this project 63 of 84 genre playlists had
  their entire contents appended three times — 3,833 rows against 2,487 distinct
  tracks — with no script re-run to explain it. `dedupe-playlists.applescript`
  removed the 1,346 surplus rows and verified clean; iCloud sync then pushed
  rows back onto *exactly* the 63 playlists the dedupe had edited, leaving the
  21 it never touched alone. Deleting the folder and rebuilding it instead
  (`organize-by-genre --replace` → `group-genres` → `lowercase-names`) propagated
  cleanly on the first try and survived a subsequent full download run. One
  coarse change replicates; 1,346 row deletions get reconciled against a server
  copy that still holds the old state. Check with
  `./dedupe-playlists.applescript --dry-run` after bulk operations, but prefer a
  rebuild over the repair when it reports duplicates.
- **Downloading the library is queued, not immediate.** `download library
  playlist 1` hands Music the whole library and returns at once; Music works
  through it in the background over hours. There is no script-readable progress:
  the `downloaded` property errors on subscription tracks and
  `whose downloaded is false` is unsupported. Sample `location` instead — it
  errors when a track has no local file — which is what
  `download-genres.applescript` does.
- **A queued download cannot be cancelled from a script, and Music may refuse to
  quit while one is running** (`quit` returns `-128 User canceled`). The queue is
  persisted and resumes on next launch. Stopping downloads is a UI action.
- **Some tracks can never download.** Twenty tracks here have cloud status
  `no longer available` — pulled from the Apple Music catalogue. They stay
  un-downloaded permanently, so any "not downloaded means new" heuristic needs
  to exclude them.
- Large libraries: operations are wrapped in `with timeout of 3600 seconds`,
  but a first run on a cold cloud library can still be slow while Music resolves
  tracks.

## Notes for editing these scripts

These scripts are built around a set of Music.app AppleScript behaviors that are
easy to get wrong. Read this before changing how playlists are created, moved,
or enumerated:

- `duplicate` takes a reference expression (`every track … whose …`), never a
  resolved list — the list form fails with `-10006`.
- `move p to folder` reparents a playlist; `set parent of p to folder` fails
  with `-1731`.
- `folder playlists` and `user playlists` are disjoint collections, and a folder
  cannot enumerate its own children — walk every playlist and check its `parent`.
- Never name a variable `lines` (or `text`, `items`, `count`, …); assignment
  throws, and an enclosing `try` will swallow it silently.
- String comparison is **case-insensitive by default** — `"Hip-Hop" is not
  "hip-hop"` evaluates false. Wrap case-sensitive tests in `considering case`.
- Never name a variable `names`, `st`, `note`, or `container` either — short
  abbreviations are not safe, and a parameter named `container` is shadowed by
  Music's own term, so `make new ... at container` fails with `-2710`.
- ASObjC method names can collide with AppleScript keywords too:
  `NSMutableSet's set()` will not parse — use `alloc()'s init()`.
- **Create; never modify.** iCloud sync reverts moves, renames and row deletions
  on synced playlists, but lets creations stand. Build the final shape in one
  pass rather than editing afterwards.
- `delete folder playlist "name"` works; `delete <reference from make new>`
  silently does nothing.
- The reference-vs-list rule is not just about `duplicate`: **bulk property
  reads need the `whose` clause re-stated too.** `set r to (every track whose …)`
  then `name of r` fails with `-1728`; `name of (every track whose …)` works.
- `osacompile -o /tmp/x.scpt <file>` syntax-checks without touching the library.
