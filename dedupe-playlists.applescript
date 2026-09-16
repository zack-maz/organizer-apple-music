#!/usr/bin/osascript
--
-- dedupe-playlists.applescript
--
-- Removes duplicate entries from the playlists inside the genre folder,
-- keeping the first occurrence of each track. Only playlist membership is
-- changed: `delete track k of <user playlist>` removes the row, never the
-- track from the library (verified).
--
-- Usage:
--   ./dedupe-playlists.applescript [--dry-run] [--folder NAME] [--json] [--progress]
--
--   --json   Append one machine-readable summary line (library, playlists,
--            rows, distinct, duplicates, touched). Used by the app.
--   --progress  Emit one machine-readable line per playlist on stderr (see the
--            progress handlers at the end of the file). Used by the app.
--

use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

property defaultFolderName : "genres"
-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

on run argv
	set folderName to defaultFolderName
	set dryRun to false
	set jsonOut to false

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--dry-run" then
			set dryRun to true
		else if a is "--json" then
			set jsonOut to true
		else if a is "--folder" then
			set i to i + 1
			if i > (count of argv) then error "--folder needs a value."
			set folderName to item i of argv
		else if a is "--progress" then
			set progressOn to true
		else if a is "-h" or a is "--help" then
			return "Usage: dedupe-playlists.applescript [--dry-run] [--folder NAME] [--json] [--progress]"
		else
			error "Unknown option: " & a
		end if
		set i to i + 1
	end repeat

	tell application "Music"
		if it is not running then launch
		set libBefore to count of tracks of library playlist 1
	end tell

	-- Capture targets by persistent ID; indexes are not stable across edits.
	set targets to {}
	tell application "Music"
		repeat with pi from 1 to (count of user playlists)
			try
				set pn to name of parent of user playlist pi
				set inScope to (pn is folderName)
				if not inScope then
					try
						if (name of parent of parent of user playlist pi) is folderName then set inScope to true
					end try
				end if
				if inScope then set end of targets to persistent ID of user playlist pi
			end try
		end repeat
	end tell
	my progressBegin(count of targets, "playlists")

	set report to {}
	set totalRemoved to 0
	set touched to 0
	set rowsTotal to 0
	set distinctTotal to 0

	repeat with pid in targets
		set thisID to pid as text
		set idx to my findByID(thisID)
		if idx > 0 then
			tell application "Music"
				set p to user playlist idx
				set plName to name of p
				set ids to persistent ID of every track of p
			end tell

			-- forward pass marks every repeat of an id already seen
			-- NSMutableSet's set() collides with AppleScript's `set` keyword; alloc/init avoids it
			set seen to current application's NSMutableSet's alloc()'s init()
			set toDelete to {}
			repeat with k from 1 to (count of ids)
				set idk to (item k of ids) as text
				set isDup to (seen's containsObject:idk) as boolean
				if isDup then
					set end of toDelete to k
				else
					seen's addObject:idk
				end if
			end repeat

			set rowsTotal to rowsTotal + (count of ids)
			set distinctTotal to distinctTotal + ((seen's |count|()) as integer)
			if (count of toDelete) is 0 then
				my progressItem("checked", plName, "", my rowsWord(count of ids) & ", no duplicates")
			else if dryRun then
				my progressItem("duplicates", plName, "", my rowsWord(count of ids) & ", " & ((count of toDelete) as text) & " duplicate")
			else
				my progressItem("removed", plName, "", ((count of toDelete) as text) & " duplicate of " & my rowsWord(count of ids))
			end if

			if (count of toDelete) > 0 then
				set touched to touched + 1
				set end of report to "  " & plName & ": " & (count of ids) & " -> " & ((count of ids) - (count of toDelete)) & "   (removing " & (count of toDelete) & ")"
				if not dryRun then
					-- delete high indexes first so lower ones stay valid
					tell application "Music"
						repeat with j from (count of toDelete) to 1 by -1
							try
								delete track (item j of toDelete) of user playlist idx
							on error e
								log "    row " & (item j of toDelete) & " of " & plName & ": " & e
							end try
						end repeat
					end tell
				end if
				set totalRemoved to totalRemoved + (count of toDelete)
			end if
		end if
	end repeat

	my progressEnd()
	tell application "Music"
		set libAfter to count of tracks of library playlist 1
	end tell

	set end of report to ""
	if dryRun then
		set end of report to "DRY RUN - would remove " & (totalRemoved as text) & " duplicate rows from " & (touched as text) & " of " & (count of targets) & " playlists."
	else
		set end of report to "Removed " & (totalRemoved as text) & " duplicate rows from " & (touched as text) & " of " & (count of targets) & " playlists."
	end if
	set end of report to "Library tracks: " & (libBefore as text) & " before, " & (libAfter as text) & " after."

	-- trailing single-line JSON for programs; the human report above is unchanged
	if jsonOut then
		set end of report to "{\"library\":" & libBefore & ",\"playlists\":" & (count of targets) & ",\"rows\":" & rowsTotal & ",\"distinct\":" & distinctTotal & ",\"duplicates\":" & totalRemoved & ",\"touched\":" & touched & "}"
	end if

	set AppleScript's text item delimiters to linefeed
	set out to report as text
	set AppleScript's text item delimiters to ""
	return out
end run

on rowsWord(n)
	if n is 1 then return "1 row"
	return (n as text) & " rows"
end rowsWord

on findByID(pid)
	tell application "Music"
		repeat with pi from 1 to (count of user playlists)
			try
				if (persistent ID of user playlist pi) is pid then return pi
			end try
		end repeat
	end tell
	return 0
end findByID

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
