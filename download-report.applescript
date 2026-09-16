#!/usr/bin/osascript
--
-- download-report.applescript
--
-- READ-ONLY. Reports how much of each genre playlist is downloaded.
--
-- This script contains no `download` command anywhere and cannot start a
-- download, by construction. Queuing lives in download-genres.applescript,
-- deliberately in a separate file so that asking "what is downloaded?" can
-- never begin downloading anything.
--
-- Music exposes no readable "is this downloaded" property on subscription
-- tracks (`downloaded` errors, `whose downloaded is false` is unsupported), so
-- presence of `location` is the proxy -- it raises an error when a track has no
-- local file. That is one Apple event per track, so a full pass over a few
-- thousand tracks takes several minutes.
--
-- Usage:
--   ./download-report.applescript [--folder NAME] [--progress]
--
--   --progress  Emit one machine-readable line per track on stderr (see the
--               progress handlers at the end of the file). Used by the app.
--

use AppleScript version "2.4"
use scripting additions

property defaultFolderName : "genres"
-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

on run argv
	set folderName to defaultFolderName

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--folder" then
			set i to i + 1
			if i > (count of argv) then error "--folder needs a value."
			set folderName to item i of argv
		else if a is "--progress" then
			set progressOn to true
		else if a is "-h" or a is "--help" then
			return "Usage: download-report.applescript [--folder NAME] [--progress]   (read-only; never downloads)"
		else
			error "Unknown option: " & a
		end if
		set i to i + 1
	end repeat

	tell application "Music"
		if it is not running then launch
	end tell

	-- capture by persistent ID; indexes shift as Music reorders
	set targets to {}
	set plannedTotal to 0
	tell application "Music"
		repeat with pi from 1 to (count of user playlists)
			try
				set inScope to ((name of parent of user playlist pi) is folderName)
				if not inScope then
					try
						if (name of parent of parent of user playlist pi) is folderName then set inScope to true
					end try
				end if
				if inScope then
					set end of targets to persistent ID of user playlist pi
					-- the total up front, one count per playlist, only when asked for progress
					if progressOn then set plannedTotal to plannedTotal + (count of tracks of user playlist pi)
				end if
			end try
		end repeat
	end tell
	my progressBegin(plannedTotal, "tracks")

	set rowsOut to {}
	set grandHave to 0
	set grandMiss to 0
	set grandStuck to 0
	set doneCount to 0

	repeat with pid in targets
		set idx to my findByID(pid as text)
		if idx > 0 then
			tell application "Music"
				set plName to name of user playlist idx
				set howMany to count of tracks of user playlist idx
			end tell
			-- names for the feed: one bulk read per playlist, never a call per track
			set titleList to {}
			set whoList to {}
			set idList to {}
			if progressOn then
				tell application "Music"
					with timeout of 3600 seconds
						set titleList to name of every track of user playlist idx
						set whoList to artist of every track of user playlist idx
						set idList to persistent ID of every track of user playlist idx
					end timeout
				end tell
			end if

			set haveN to 0
			set missN to 0
			set stuckN to 0
			tell application "Music"
				with timeout of 3600 seconds
					repeat with k from 1 to howMany
						set gotFile to true
						try
							get location of track k of user playlist idx
						on error
							set gotFile to false
						end try
						if gotFile then
							set haveN to haveN + 1
							set rowKind to "downloaded"
						else
							set gone to false
							try
								if (cloud status of track k of user playlist idx) is no longer available then set gone to true
							end try
							if gone then
								set stuckN to stuckN + 1
								set rowKind to "unavailable"
							else
								set missN to missN + 1
								set rowKind to "pending"
							end if
						end if
						my progressItemID(rowKind, my progressAt(idList, k), plName, my progressAt(whoList, k), my progressAt(titleList, k))
					end repeat
				end timeout
			end tell

			set grandHave to grandHave + haveN
			set grandMiss to grandMiss + missN
			set grandStuck to grandStuck + stuckN
			if missN is 0 and howMany > 0 then set doneCount to doneCount + 1

			set suffix to ""
			if stuckN > 0 then set suffix to "   (" & stuckN & " unavailable)"
			set rowsOut to rowsOut & {"  " & plName & ": " & haveN & "/" & howMany & suffix}
			log "  " & plName & ": " & haveN & "/" & howMany & suffix
		end if
	end repeat

	my progressEnd()
	set total to grandHave + grandMiss + grandStuck
	set pct to 0
	if total > 0 then set pct to (grandHave * 100) / total

	set rowsOut to rowsOut & {""}
	set rowsOut to rowsOut & {"Downloaded:  " & grandHave & " of " & total & "  (" & (round pct) & "%)"}
	set rowsOut to rowsOut & {"Pending:     " & grandMiss}
	set rowsOut to rowsOut & {"Unavailable: " & grandStuck & "  (pulled from the catalogue - can never download)"}
	set rowsOut to rowsOut & {"Complete:    " & doneCount & " of " & (count of targets) & " playlists"}
	set rowsOut to rowsOut & {""}
	set rowsOut to rowsOut & {"Read-only. To queue the gaps, run download-genres.applescript."}

	set AppleScript's text item delimiters to linefeed
	set outText to rowsOut as text
	set AppleScript's text item delimiters to ""
	return outText
end run

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
