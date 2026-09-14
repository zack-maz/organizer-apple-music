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
--   ./download-report.applescript [--folder NAME]
--

use AppleScript version "2.4"
use scripting additions

property defaultFolderName : "genres"

on run argv
	set folderName to defaultFolderName

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--folder" then
			set i to i + 1
			if i > (count of argv) then error "--folder needs a value."
			set folderName to item i of argv
		else if a is "-h" or a is "--help" then
			return "Usage: download-report.applescript [--folder NAME]   (read-only; never downloads)"
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
	tell application "Music"
		repeat with pi from 1 to (count of user playlists)
			try
				set inScope to ((name of parent of user playlist pi) is folderName)
				if not inScope then
					try
						if (name of parent of parent of user playlist pi) is folderName then set inScope to true
					end try
				end if
				if inScope then set end of targets to persistent ID of user playlist pi
			end try
		end repeat
	end tell

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
						else
							set gone to false
							try
								if (cloud status of track k of user playlist idx) is no longer available then set gone to true
							end try
							if gone then
								set stuckN to stuckN + 1
							else
								set missN to missN + 1
							end if
						end if
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
