//
// Docs.swift
//
// What each command does, when to reach for it, and its flags -- condensed
// from SCRIPTS.md, which stays the full reference. Text only; the Docs tab
// lays it out.
//

import Foundation
import OrganizerCore

struct FlagDoc: Identifiable {
    let flag: String
    let meaning: String
    var id: String { flag }
}

struct CommandDoc: Identifiable {
    let kind: ActionKind
    /// What it does, in two or three sentences.
    let does: String
    /// When to reach for it.
    let when: String
    let flags: [FlagDoc]
    var id: String { kind.id }
}

enum Docs {
    /// Read before the entries: the rule every script is built around.
    static let preamble = "Every script drives Music.app through AppleScript. Nothing touches audio files and no track is ever moved or deleted; only playlists are created and removed. The one rule: create, never modify. iCloud sync reverts renames, moves and row edits on synced playlists but lets creations stand, so the scripts build the final shape in one pass and rebuild rather than repair."

    static let dryRunNote = "In this app every command that changes the library runs with --dry-run first. The console shows the plan, then offers Run for real. The Downloads commands are disabled: queued downloads can stall indefinitely, and a script can neither see why nor fix it. They are documented below for command-line use only."

    static let all: [CommandDoc] = ActionKind.allCases.map(doc(for:))

    /// Every script takes it; the app always passes it.
    static let progressFlag = FlagDoc(
        flag: "--progress",
        meaning: "Report each track or playlist as it is handled, on stderr, in a form the app reads. The console turns it into the progress bar and the live feed; the human output is unchanged. Off on the command line unless passed.")

    static func doc(for kind: ActionKind) -> CommandDoc {
        switch kind {
        case .buildGenres:
            return CommandDoc(
                kind: kind,
                does: "Two modes, chosen by whether the genre folder already exists. With no folder, or with --replace, it does the full build: the genre folder, its parent folders (13 by default) and one playlist per genre, each made directly inside its parent, already lowercase, then filled, in one creation pass. With the folder present and no --replace it is incremental: only tracks not yet in any genre playlist are touched. A track whose genre already has a playlist is appended to it; a genre with no playlist yet gets one created in full inside its parent folder, and the parent is created if it is the first of its group. Nothing existing is renamed, moved or removed. Genres are folded to lowercase before uniquing and nothing is merged beyond case; a genre missing from the groups table is created at the top of the folder and reported under UNMAPPED.",
                when: "Unchecked, after adding music: it files only what is new. Checked, for the first build, when dedupe-playlists reports duplicate rows, or when the tree needs to be certain. Appending rows to a synced playlist is still a modification and whether iCloud keeps those rows is not established (row deletions were reverted; additions have not been tested). Check with whats-new a day later; if the rows vanished, --replace remains the sure path. Back up before --replace: deleting a playlist is permanent and syncs to every device.",
                flags: [
                    FlagDoc(flag: "--dry-run", meaning: "Print the plan and any unmapped genres; create nothing."),
                    FlagDoc(flag: "--replace", meaning: "Delete an existing folder of the same name first and rebuild everything. Without it, an existing folder is kept and only new tracks are filed."),
                    FlagDoc(flag: "--folder NAME", meaning: "Folder to create or add to (default genres)."),
                    FlagDoc(flag: "--min-tracks N", meaning: "Skip genres with fewer than N tracks (default 1). In the incremental mode it only gates new playlists."),
                ] + [Docs.progressFlag])
        case .whatsNew:
            return CommandDoc(
                kind: kind,
                does: "Lists the songs that are in the library but not in any genre playlist. It compares the library against the genre tree directly, so the answer is exact, not a heuristic. It deliberately ignores download state: Music cannot report it on subscription tracks, and the tracks Apple has pulled never download at all.",
                when: "After adding music, to see what still needs filing, and after a rebuild to confirm that every track is filed. Refresh runs it for the overview numbers.",
                flags: [
                    FlagDoc(flag: "--days N", meaning: "Also list everything added in the last N days, filed or not."),
                    FlagDoc(flag: "--all", meaning: "Do not cap the lists at 40 entries."),
                    FlagDoc(flag: "--folder NAME", meaning: "Genre folder to compare against (default genres)."),
                    FlagDoc(flag: "--json", meaning: "Append one machine-readable summary line after the report."),
                ] + [Docs.progressFlag])
        case .dedupePlaylists:
            return CommandDoc(
                kind: kind,
                does: "Removes repeated tracks from the playlists inside the genre folder, keeping the first occurrence. Only playlist membership changes; a track is never removed from the library, and the script reports the library count before and after so you can confirm that.",
                when: "Run the dry run after bulk operations to check rows against distinct tracks; the overview shows its duplicate count. When it does find duplicates, prefer a rebuild: sync has been seen pushing rows back onto exactly the playlists a dedupe had edited, while a deleted-and-rebuilt folder propagated cleanly.",
                flags: [
                    FlagDoc(flag: "--dry-run", meaning: "Report what would be removed; change nothing."),
                    FlagDoc(flag: "--folder NAME", meaning: "Genre folder to scan (default genres)."),
                    FlagDoc(flag: "--json", meaning: "Append one summary line: rows, distinct, duplicates."),
                ] + [Docs.progressFlag])
        case .markUnavailable:
            return CommandDoc(
                kind: kind,
                does: "Gathers every track whose cloud status is no longer available (pulled from the Apple Music catalogue) into one playlist, wont download. These tracks stay in the library but can never download, so without this they look permanently un-downloaded. The playlist is created at the top level, deliberately outside the genre folder, so a rebuild does not delete it. It is deleted and recreated rather than edited.",
                when: "After the first build, and whenever you want the list refreshed. Twenty tracks were in this state last time it was measured.",
                flags: [
                    FlagDoc(flag: "--dry-run", meaning: "List the tracks; create nothing."),
                    FlagDoc(flag: "--name NAME", meaning: "Playlist name (default wont download)."),
                ] + [Docs.progressFlag])
        case .downloadReport:
            return CommandDoc(
                kind: kind,
                does: "Reports how much of each genre playlist is downloaded, and totals. Read-only: the script contains no download command and cannot start one, by construction. Presence of a local file location is the proxy for download state, which costs one Apple event per track, so a full pass takes several minutes.",
                when: "To check download coverage or progress with no risk of queuing anything.",
                flags: [
                    FlagDoc(flag: "--folder NAME", meaning: "Genre folder to walk (default genres)."),
                ] + [Docs.progressFlag])
        case .downloadGenres:
            return CommandDoc(
                kind: kind,
                does: "The same walk as download-report, then it queues every track that has no local file. Queuing is instant; Music works through the queue in the background over hours, and a queued download cannot be cancelled from a script. Tracks that are no longer available are counted separately, since they can never download.",
                when: "When you want the library offline. Re-run the dry run any time to see progress. Stopping this in the console stops the script, not a download Music has already queued.",
                flags: [
                    FlagDoc(flag: "--dry-run", meaning: "Coverage report only; queue nothing."),
                    FlagDoc(flag: "--folder NAME", meaning: "Genre folder to walk (default genres)."),
                ] + [Docs.progressFlag])
        case .watchDownloads:
            return CommandDoc(
                kind: kind,
                does: "Watches the genre playlists and reports each track the moment it finishes downloading. It reads the download state once, the way download-report does, then every interval checks only the tracks still pending: one bulk read per playlist plus a location read per pending track, never for a track already known to be downloaded. Read-only: it contains no download command.",
                when: "After download-genres has queued the gaps; the app starts it for you when a real run queued anything. Stop ends the watch, not the downloads Music is already working through. Run it on its own any time to see what is still pending and what has landed since.",
                flags: [
                    FlagDoc(flag: "--interval N", meaning: "Seconds between checks (default 30)."),
                    FlagDoc(flag: "--once", meaning: "One check after the interval, then exit."),
                    FlagDoc(flag: "--folder NAME", meaning: "Genre folder to watch (default genres)."),
                ] + [Docs.progressFlag])
        case .backupPlaylists:
            return CommandDoc(
                kind: kind,
                does: "Writes one TSV per top-level playlist (persistent ID, title, artist, album) plus a MANIFEST.tsv listing every playlist and its track count. Playlists inside the genre folder are skipped, since they are regenerable from the library.",
                when: "Before any rebuild or anything else that deletes playlists. The confirm bar for a build-genres run with --replace offers to run it first.",
                flags: [
                    FlagDoc(flag: "output-dir", meaning: "Where to write. The app passes <backups folder>/playlists-YYYYMMDD-HHMMSS; on the command line it defaults to backups/ next to the script."),
                ] + [Docs.progressFlag])
        case .restorePlaylists:
            return CommandDoc(
                kind: kind,
                does: "Recreates playlists from a backup folder, matching tracks by persistent ID. With no names it restores everything in the folder except Apple's built-in smart playlists (Music, Music Videos, Favorite Songs). It only recovers songs still in the library; a track removed since the backup is skipped and the playlist is recreated without it.",
                when: "After losing a playlist, or to bring a playlist back from an older backup.",
                flags: [
                    FlagDoc(flag: "--dry-run", meaning: "List what the backup holds; create nothing and never talk to Music."),
                    FlagDoc(flag: "backup-dir", meaning: "The playlists-YYYYMMDD-HHMMSS folder to read."),
                    FlagDoc(flag: "PlaylistName …", meaning: "Optional names to restore; anything else in the folder is left alone."),
                ] + [Docs.progressFlag])
        }
    }
}
