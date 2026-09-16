#!/usr/bin/osascript
--
-- watch-downloads.applescript
--
-- READ-ONLY. Watches the genre playlists and reports each track the moment it
-- finishes downloading. Pair it with download-genres.applescript, which only
-- queues: Music works through the queue in the background over hours and
-- reports no progress, so this polls for the one signal that exists -- a track
-- gaining a `location` -- and says which song it was.
--
-- This script contains no `download` command and cannot start a download.
--
-- On start it walks the genre playlists once, the same way download-report
-- does (one `location` read per track), and remembers every track that has no
-- local file and is not `no longer available`. Then, every --interval seconds,
-- for each playlist that still has pending tracks: one bulk read of the
-- playlist's persistent IDs, then a `location` read only for the tracks still
-- pending. A track known to be downloaded is never asked again. Playlists are
-- re-found by persistent ID on every pass, so index drift cannot bite. It
-- exits when nothing is pending. Kill it any time (the app's Stop does):
-- nothing is written, so nothing is left half-done.
--
-- Usage:
--   ./watch-downloads.applescript [--folder NAME] [--interval SECONDS] [--once] [--progress]
--
--   --interval N  Seconds between checks (default 30).
--   --once        One check after the interval, then exit.
--   --progress    Emit one machine-readable line per track on stderr: kind=pending
--                 for every pending track at the start, then kind=downloaded as
--                 each one lands, each carrying id=<persistent ID> so the app
--                 updates the row in place. Used by the app.
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
	set intervalSecs to 30
	set onlyOnce to false

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--folder" then
			set i to i + 1
			if i > (count of argv) then error "--folder needs a value."
			set folderName to item i of argv
		else if a is "--interval" then
			set i to i + 1
			if i > (count of argv) then error "--interval needs a value."
			set intervalSecs to (item i of argv) as integer
			if intervalSecs < 1 then error "--interval must be at least 1 second."
		else if a is "--once" then
			set onlyOnce to true
		else if a is "--progress" then
			set progressOn to true
		else if a is "-h" or a is "--help" then
			return "Usage: watch-downloads.applescript [--folder NAME] [--interval SECONDS] [--once] [--progress]   (read-only; never downloads)"
		else
			error "Unknown option: " & a
		end if
		set i to i + 1
	end repeat

	tell application "Music"
		if it is not running then launch
	end tell

	-- the genre playlists, by persistent ID; indexes shift as Music reorders
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

	-- first pass: what is still waiting, playlist by playlist. Three bulk reads
	-- per playlist (IDs, titles, artists), then one `location` read per track,
	-- exactly what download-report costs.
	log "Reading download state..."
	set watchList to {} -- {playlist persistent ID, playlist name, {{track ID, artist, title}, ...}}
	set pendingTotal to 0
	set haveTotal to 0
	set stuckTotal to 0
	repeat with pid in targets
		set plPID to pid as text
		set idx to my findByID(plPID)
		if idx > 0 then
			tell application "Music"
				set plName to name of user playlist idx
				with timeout of 3600 seconds
					set trackIDs to persistent ID of every track of user playlist idx
					set titleList to name of every track of user playlist idx
					set whoList to artist of every track of user playlist idx
				end timeout
			end tell
			set pendingRows to {}
			tell application "Music"
				with timeout of 3600 seconds
					repeat with k from 1 to (count of trackIDs)
						set gotFile to true
						try
							get location of track k of user playlist idx
						on error
							set gotFile to false
						end try
						if gotFile then
							set haveTotal to haveTotal + 1
						else
							set gone to false
							try
								if (cloud status of track k of user playlist idx) is no longer available then set gone to true
							end try
							if gone then
								set stuckTotal to stuckTotal + 1
							else
								set end of pendingRows to {(item k of trackIDs) as text, my progressAt(whoList, k), my progressAt(titleList, k)}
							end if
						end if
					end repeat
				end timeout
			end tell
			if (count of pendingRows) > 0 then
				set end of watchList to {plPID, plName, pendingRows}
				set pendingTotal to pendingTotal + (count of pendingRows)
				log "  " & plName & ": " & (count of pendingRows) & " pending"
			end if
		end if
	end repeat

	my progressBegin(pendingTotal, "downloads")
	repeat with wl in watchList
		repeat with pr in (item 3 of wl)
			my progressMarkID("pending", item 1 of pr, item 2 of wl, item 2 of pr, item 3 of pr)
		end repeat
	end repeat
	log "Downloaded " & haveTotal & ", pending " & pendingTotal & ", unavailable " & stuckTotal & "."
	if pendingTotal is 0 then
		my progressEnd()
		return "Nothing pending: every track that can download has. (" & stuckTotal & " unavailable, can never download.)"
	end if
	log "Watching every " & intervalSecs & " s. Stop any time; nothing is written."

	-- later passes: per playlist that still has pending tracks, one bulk read
	-- of the IDs to find where they sit now, then `location` for those only
	set landed to 0
	set passes to 0
	repeat
		delay intervalSecs
		set passes to passes + 1
		set nextWatch to {}
		repeat with wl in watchList
			set plPID to item 1 of wl
			set plName to item 2 of wl
			set pendingRows to item 3 of wl
			set stillRows to pendingRows
			set idx to my findByID(plPID)
			if idx > 0 then
				tell application "Music"
					with timeout of 3600 seconds
						set trackIDs to persistent ID of every track of user playlist idx
					end timeout
				end tell
				-- where each track ID sits in the playlist right now
				set positions to {}
				repeat with k from 1 to (count of trackIDs)
					set end of positions to k
				end repeat
				set posByID to current application's NSDictionary's dictionaryWithObjects:positions forKeys:trackIDs
				set stillRows to {}
				repeat with pr in pendingRows
					set trackPID to item 1 of pr
					set kObj to posByID's objectForKey:trackPID
					set gotFile to false
					if kObj is not missing value then
						set k to kObj as integer
						tell application "Music"
							try
								get location of track k of user playlist idx
								set gotFile to true
							end try
						end tell
					end if
					if gotFile then
						set landed to landed + 1
						log "  " & plName & ": " & (item 2 of pr) & " — " & (item 3 of pr)
						my progressItemID("downloaded", trackPID, plName, item 2 of pr, item 3 of pr)
					else
						set end of stillRows to contents of pr
					end if
				end repeat
			end if
			if (count of stillRows) > 0 then set end of nextWatch to {plPID, plName, stillRows}
		end repeat
		set watchList to nextWatch
		set remaining to pendingTotal - landed
		log "  pass " & passes & ": " & landed & " downloaded, " & remaining & " pending"
		if remaining is 0 or onlyOnce then exit repeat
	end repeat
	my progressEnd()

	if pendingTotal - landed is 0 then return "All " & pendingTotal & " pending tracks have downloaded."
	return (landed as text) & " of " & pendingTotal & " pending tracks downloaded while watching; " & (pendingTotal - landed) & " still pending."
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
