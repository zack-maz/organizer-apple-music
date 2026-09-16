# STATE

Where this project actually stands. Update this file when the library state
changes; it is the first thing to read when picking the work back up.

**Last updated:** 2026-09-13, after regenerating the genre folder.

---

## Library right now

| | |
| --- | ---: |
| Tracks in library | 2,494 |
| Genre playlists | 84 |
| Parent folders | 13 (inside `genres`) |
| Tracks filed | 2,494 (rows = distinct, 0 duplicates) |
| Distinct albums in library | 1,669 |
| Download state | 1,798 of 2,495 downloaded (72%), 677 pending, 20 unavailable — measured 2026-09-16 with `download-report` |

Everything is lowercase — the `genres` folder, all 13 parent folders, all 84
playlists. Nothing is loose at the root. `wont download` sits at the **top
level**, deliberately outside `genres` so `--replace` does not delete it.

Verified immediately after the 2026-09-13 regenerate: `folders=14 mixed-case=0`,
`playlists nested=84 loose=0 mixed-case=0`, `rows=2494 distinct=2494
duplicated=0`.

## Settled: creation survives sync, modification does not

This was the open question for a week. **It is now answered.**

A build made on 2026-09-05 was left untouched for eight days. Nesting and casing
came through completely intact — 84 playlists still nested in their parent
folders, every name still lowercase, nothing loose at the root. Those are exactly
the properties that had been reverted within hours every time they were applied
as *edits* (`move`, rename) rather than baked in at creation.

| Change | Kind | Outcome |
| --- | --- | --- |
| Renamed 97 playlists to lowercase | modify | reverted within hours |
| Moved 84 playlists into parent folders | modify | reverted within hours |
| Created them already-nested and already-lowercase | create | **held for 8 days** |

`build-genres.applescript` issues **no `move` and no rename** for this reason.
Do not reintroduce post-hoc edits; build the final shape in one pass.

## Unsettled: membership duplicates itself

Playlist *contents* still drift, and this is now understood differently than it
was on 2026-09-05.

Observed twice: contents appended three times, then — eight days after a clean
build, with no script having edited a single row — every playlist doubled
(4,974 rows against 2,487 distinct). Distinct track IDs stayed correct both
times, so **nothing is lost**; only duplicate membership rows accumulate.

**The earlier diagnosis in this file was wrong.** It attributed the recurrence to
a sync conflict with local row deletions. That cannot be right: it recurred with
no local edits at all. Whatever causes it is independent of anything this project
does.

**Treat regeneration as routine maintenance**, not repair:

```sh
./dedupe-playlists.applescript --dry-run   # rows vs distinct; flags the drift
./build-genres.applescript --replace       # fixes it, and picks up new tracks
```

## Downloads — deliberately not run

The download queue was **not touched this session.** As of 2026-09-05 roughly
1,112 of 2,487 tracks had local files; eight days on, that number is unknown and
should not be assumed.

Download tooling is split in two so that checking can never start a download:

- `download-report.applescript` — **read-only**, contains no `download` command
  at all. Use this to check coverage.
- `download-genres.applescript` — reports *and* queues the gaps.

A queued download cannot be cancelled from a script, and Music may refuse to quit
while one runs. Stopping it is a UI action.

## Known limits

- **20 tracks can never download** (cloud status `no longer available` — pulled
  from the Apple Music catalogue). Collected in `wont download`.
- **Download state is not scriptable.** `downloaded` errors on subscription
  tracks and `whose downloaded is false` is unsupported. Presence of `location`
  is the only proxy, at one Apple event per track.
- **"Not downloaded" cannot mean "new."** That was the original idea and it does
  not work, because the 20 unavailable tracks are permanently un-downloaded.
  `whats-new.applescript` answers the real question by comparing the library
  against the genre tree — exact, not a heuristic.
- **Genres are not merged**, by explicit preference. `hip-hop`, `rap`,
  `hip-hop/rap` and `uk hip-hop` are four playlists sharing one parent. Only case
  is folded.
- **Albums are not used as an organizing unit.** 1,669 distinct albums across
  2,494 tracks — averaging 1.5 tracks each — so per-album playlists would be
  noise. Genre is the useful grouping for this library.

## Not established

- What causes membership to duplicate. Independent of this project's edits;
  beyond that, unknown.
- Whether playlist track order survives a `move`.
- Behavior on a local-only (non-iCloud) library — everything here ran against an
  iCloud-synced library that is ~99% subscription tracks.

## Safety notes

- `backups/` is **gitignored** — it holds the full contents of the music library
  (titles, artists, albums) and does not belong in a public repo.
- Playlist deletion is permanent: no trash, no undo, and it syncs to other
  devices. Take a backup before anything destructive.
- A script's success message is not evidence. Verify against the library, and
  check nesting and casing, not just track counts.

## Reference

The Music.app AppleScript behaviors these scripts depend on — which commands
work, which fail and with what error codes — are summarised at the end of
SCRIPTS.md under "Notes for editing these scripts".
