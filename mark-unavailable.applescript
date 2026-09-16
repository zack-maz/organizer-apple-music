#!/usr/bin/osascript
--
-- mark-unavailable.applescript
--
-- Collects every track Apple has pulled from the catalogue (cloud status
-- `no longer available`) into one playlist. These can never download, so they
-- would otherwise sit in the library looking permanently un-downloaded and
-- defeat any "not downloaded means new" check.
--
-- The playlist is created at the top level, deliberately outside the genre
-- folder, so `organize-by-genre --replace` does not take it with the folder.
--
-- Rebuilds rather than repairs: the playlist is deleted and recreated, because
-- row-level edits to a synced playlist get reconciled against the server copy.
--
-- Usage:
--   ./mark-unavailable.applescript [--dry-run] [--name NAME] [--progress]
--
--   --progress  Emit one machine-readable line per track on stderr (see the
--               progress handlers at the end of the file). Used by the app.
--

use AppleScript version "2.4"
use scripting additions

property defaultName : "wont download"
-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

on run argv
	set plName to defaultName
	set dryRun to false

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--dry-run" then
			set dryRun to true
		else if a is "--name" then
			set i to i + 1
			if i > (count of argv) then error "--name needs a value."
			set plName to item i of argv
		else if a is "--progress" then
			set progressOn to true
		else if a is "-h" or a is "--help" then
			return "Usage: mark-unavailable.applescript [--dry-run] [--name NAME] [--progress]"
		else
			error "Unknown option: " & a
		end if
		set i to i + 1
	end repeat

	tell application "Music"
		if it is not running then launch
		set lib to library playlist 1
		-- Each of these must re-state the `whose` clause. Storing the result in a
		-- variable turns it into a resolved list, and `name of <list>` fails with
		-- -1728 -- the same reference-vs-list rule that governs `duplicate`.
		with timeout of 1800 seconds
			set howMany to count of (every track of lib whose cloud status is no longer available)
			set titleList to name of (every track of lib whose cloud status is no longer available)
			set whoList to artist of (every track of lib whose cloud status is no longer available)
		end timeout
	end tell

	set rowsOut to {}
	my progressBegin(howMany, "tracks")
	repeat with k from 1 to howMany
		set rowsOut to rowsOut & {"  " & (item k of whoList) & " — " & (item k of titleList)}
		my progressItem("unavailable", plName, item k of whoList, item k of titleList)
	end repeat

	if dryRun then
		set rowsOut to rowsOut & {"", "DRY RUN - would put " & howMany & " tracks in \"" & plName & "\"."}
		my progressEnd()
		return my joinUp(rowsOut)
	end if

	if howMany is 0 then
		tell application "Music"
			if exists user playlist plName then delete user playlist plName
		end tell
		my progressEnd()
		return "No unavailable tracks. Nothing to mark."
	end if

	tell application "Music"
		if exists user playlist plName then delete user playlist plName
		set p to make new user playlist with properties {name:plName}
		with timeout of 1800 seconds
			duplicate (every track of lib whose cloud status is no longer available) to p
		end timeout
		set landed to count of tracks of p
	end tell

	my progressMark("created", plName, (landed as text) & " tracks")
	my progressEnd()
	set rowsOut to rowsOut & {"", "Put " & landed & " of " & howMany & " unavailable tracks in \"" & plName & "\"."}
	return my joinUp(rowsOut)
end run

on joinUp(lst)
	set AppleScript's text item delimiters to linefeed
	set outText to lst as text
	set AppleScript's text item delimiters to ""
	return outText
end joinUp

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
