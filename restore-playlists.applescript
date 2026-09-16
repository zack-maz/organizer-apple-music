#!/usr/bin/osascript
--
-- restore-playlists.applescript
--
-- Recreates playlists from a backup directory written by backup-playlists.applescript.
-- Each .tsv holds one playlist: persistentID <tab> title <tab> artist <tab> album.
-- Tracks are matched by persistent ID against the library.
--
-- Usage:
--   ./restore-playlists.applescript [--dry-run] [--progress] backups/playlists-YYYYMMDD-HHMMSS [PlaylistName ...]
--
-- With no playlist names, every .tsv in the directory is restored except the
-- Apple built-ins (Music, Music Videos, Favorite Songs), which are smart
-- playlists that Music manages itself.
--
-- --dry-run lists what the backup holds and creates nothing. It never talks to
-- Music, so it cannot say how many of those tracks are still in the library.
--
-- --progress emits one machine-readable line per track restored on stderr (see
-- the progress handlers at the end of the file). Used by the app.
--

use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

property builtIns : {"Music", "Music Videos", "Favorite Songs"}
-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

on run argv
	set usage to "Usage: restore-playlists.applescript [--dry-run] [--progress] <backup-dir> [PlaylistName ...]"
	set dryRun to false
	set positional to {}
	repeat with a in argv
		set av to a as text
		if av is "--dry-run" then
			set dryRun to true
		else if av is "--progress" then
			set progressOn to true
		else if av is "-h" or av is "--help" then
			return usage
		else
			set end of positional to av
		end if
	end repeat
	if (count of positional) < 1 then error usage
	set backupDir to item 1 of positional
	set wanted to {}
	if (count of positional) > 1 then set wanted to items 2 thru -1 of positional

	set fm to current application's NSFileManager's defaultManager()
	set allFiles to (fm's contentsOfDirectoryAtPath:backupDir |error|:(missing value)) as list

	-- read every chosen .tsv first, so the total is known before anything is
	-- created: one entry per playlist, {name, {persistent IDs}, {titles}, {artists}}
	set restorePlan to {}
	set idTotal to 0
	repeat with f in allFiles
		set fname to f as text
		if fname ends with ".tsv" and fname is not "MANIFEST.tsv" then
			set fpath to backupDir & "/" & fname
			set blob to (current application's NSString's stringWithContentsOfFile:fpath encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)) as text
			set rows to paragraphs of blob

			-- first line is "# <original playlist name>"
			set plName to text 3 thru -1 of (item 1 of rows)
			set doIt to true
			if (count of wanted) > 0 then
				set doIt to (wanted contains plName)
			else if builtIns contains plName then
				set doIt to false
			end if

			if doIt then
				set ids to {}
				set titleVals to {}
				set whoVals to {}
				repeat with r in rows
					set rt to r as text
					if rt is not "" and rt does not start with "#" then
						set AppleScript's text item delimiters to tab
						set cols to text items of rt
						set AppleScript's text item delimiters to ""
						set pid to item 1 of cols
						if pid is not "" then
							set end of ids to pid
							set end of titleVals to my progressAt(cols, 2)
							set end of whoVals to my progressAt(cols, 3)
						end if
					end if
				end repeat
				set end of restorePlan to {plName, ids, titleVals, whoVals}
				set idTotal to idTotal + (count of ids)
			end if
		end if
	end repeat

	set restored to 0
	set totalAdded to 0
	set report to {}

	if dryRun then
		-- report the backup's contents only; Music is never asked anything
		my progressBegin(count of restorePlan, "playlists")
		repeat with rp in restorePlan
			set plName to item 1 of rp
			set ids to item 2 of rp
			set restored to restored + 1
			set totalAdded to totalAdded + (count of ids)
			set end of report to "  " & plName & ": " & ((count of ids) as text) & " tracks in backup"
			log "  " & plName & ": " & ((count of ids) as text) & " tracks in backup"
			my progressItem("pending", plName, "", ((count of ids) as text) & " tracks in backup")
		end repeat
		my progressEnd()
		return "DRY RUN - would restore " & (restored as text) & " playlists holding " & (totalAdded as text) & " track IDs. Tracks no longer in the library are skipped on the real run."
	end if

	my progressBegin(idTotal, "tracks")
	repeat with rp in restorePlan
		set plName to item 1 of rp
		set ids to item 2 of rp
		set titleVals to item 3 of rp
		set whoVals to item 4 of rp
		tell application "Music"
			set p to make new user playlist with properties {name:plName}
		end tell
		my progressMark("created", plName, ((count of ids) as text) & " tracks in backup")
		set added to 0
		repeat with k from 1 to (count of ids)
			set pid to item k of ids
			set gotIt to false
			tell application "Music"
				try
					duplicate (every track of library playlist 1 whose persistent ID is pid) to p
					set gotIt to true
				end try
			end tell
			if gotIt then
				set added to added + 1
				my progressItem("restored", plName, item k of whoVals, item k of titleVals)
			else
				my progressItem("missing", plName, item k of whoVals, item k of titleVals)
			end if
		end repeat
		set restored to restored + 1
		set totalAdded to totalAdded + added
		set end of report to "  " & plName & ": " & (added as text) & "/" & ((count of ids) as text)
		log "  " & plName & ": " & (added as text) & "/" & ((count of ids) as text)
	end repeat
	my progressEnd()

	return "Restored " & (restored as text) & " playlists, " & (totalAdded as text) & " tracks matched."
end run

-- Progress protocol, on with --progress (off by default, so the CLI output is
-- unchanged). One machine-readable line per event, via `log`, so it lands on
-- stderr as it happens; the app turns them into a progress bar and live feed.
--
--   @@ begin <TAB> total=N <TAB> unit=tracks|playlists|downloads
--   @@ item  <TAB> i=n <TAB> of=N <TAB> kind=added <TAB> id=… <TAB> playlist=… <TAB> artist=… <TAB> title=…
--   @@ end
--
-- Fields are tab-separated key=value pairs (names may hold spaces, so tab is
-- the separator); tabs and newlines inside a value become spaces. An item
-- without i/of is an uncounted event, such as a playlist created or queued.
-- `id` is the track's persistent ID when known: a later item with the same id
-- updates the earlier row in the app (pending -> downloaded) instead of adding
-- one. Items without id always add a row.
on progressBegin(howMany, unitName)
	if not progressOn then return
	set progressDone to 0
	set progressTotal to howMany
	my progressEmit("begin", {{"total", howMany}, {"unit", unitName}})
end progressBegin

-- one counted item: advances n of N
on progressItem(itemKind, plVal, whoVal, titleVal)
	my progressRow(true, itemKind, "", plVal, whoVal, titleVal)
end progressItem

-- one counted item with a track identity
on progressItemID(itemKind, idVal, plVal, whoVal, titleVal)
	my progressRow(true, itemKind, idVal, plVal, whoVal, titleVal)
end progressItemID

-- an uncounted event, e.g. a playlist created or queued
on progressMark(itemKind, plVal, titleVal)
	my progressRow(false, itemKind, "", plVal, "", titleVal)
end progressMark

-- an uncounted event with a track identity, e.g. a track still pending
on progressMarkID(itemKind, idVal, plVal, whoVal, titleVal)
	my progressRow(false, itemKind, idVal, plVal, whoVal, titleVal)
end progressMarkID

on progressRow(counted, itemKind, idVal, plVal, whoVal, titleVal)
	if not progressOn then return
	set pairs to {}
	if counted then
		set progressDone to progressDone + 1
		set pairs to {{"i", progressDone}, {"of", progressTotal}}
	end if
	set pairs to pairs & {{"kind", itemKind}}
	if (idVal as text) is not "" then set pairs to pairs & {{"id", idVal}}
	set pairs to pairs & {{"playlist", plVal}, {"artist", whoVal}, {"title", titleVal}}
	my progressEmit("item", pairs)
end progressRow

on progressEnd()
	if not progressOn then return
	my progressEmit("end", {})
end progressEnd

on progressEmit(evName, pairs)
	set outParts to {"@@ " & evName}
	repeat with pr in pairs
		set end of outParts to (item 1 of pr) & "=" & my progressClean(item 2 of pr)
	end repeat
	set AppleScript's text item delimiters to tab
	set progressLine to outParts as text
	set AppleScript's text item delimiters to ""
	log progressLine
end progressEmit

-- a value as one line: missing value -> "", tabs and newlines -> spaces
on progressClean(v)
	if v is missing value then return ""
	set s to v as text
	set AppleScript's text item delimiters to {tab, linefeed, return}
	set bits to text items of s
	set AppleScript's text item delimiters to " "
	set s to bits as text
	set AppleScript's text item delimiters to ""
	return s
end progressClean

-- item k of a bulk-read list, or "" when the list is shorter (a playlist
-- that changed under us); never errors
on progressAt(lst, k)
	if k > (count of lst) then return ""
	return item k of lst
end progressAt
