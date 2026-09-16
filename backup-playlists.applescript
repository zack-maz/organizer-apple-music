#!/usr/bin/osascript
--
-- backup-playlists.applescript
--
-- Writes one TSV per playlist (persistentID, title, artist, album) plus a
-- MANIFEST.tsv, so playlists can be recreated later by restore-playlists.applescript.
-- Everything outside the "genres" folder is captured, including Apple's built-ins.
--
-- Usage:
--   ./backup-playlists.applescript [--progress] [output-dir]
--
--   --progress  Emit one machine-readable line per playlist on stderr (see the
--               progress handlers at the end of the file). Used by the app.
--
-- With no argument it creates backups/playlists-YYYYMMDD-HHMMSS next to this script.
--

-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

on run argv
	set outDir to ""
	repeat with a in argv
		set av to a as text
		if av is "--progress" then
			set progressOn to true
		else if av is "-h" or av is "--help" then
			return "Usage: backup-playlists.applescript [--progress] [output-dir]"
		else if outDir is "" then
			set outDir to av
		else
			error "Unknown option: " & av
		end if
	end repeat
	if outDir is "" then
		set here to POSIX path of ((path to me as text) & "::")
		set stamp to do shell script "date +%Y%m%d-%H%M%S"
		set outDir to here & "backups/playlists-" & stamp
	end if
	do shell script "mkdir -p " & quoted form of outDir

	-- pick the playlists first (top level, not the genre folder), so the
	-- total is known before the first file is written
	set chosenIdx to {}
	set chosenNames to {}
	tell application "Music"
		set total to count of user playlists
		repeat with i from 1 to total
			set nm to ""
			try
				set nm to name of user playlist i
			end try
			set isTop to true
			try
				get parent of user playlist i
				set isTop to false
			end try
			if isTop and nm is not "genres" and nm is not "" then
				set end of chosenIdx to i
				set end of chosenNames to nm
			end if
		end repeat
	end tell
	my progressBegin(count of chosenIdx, "playlists")

	set manifest to {}
	tell application "Music"
		repeat with ci from 1 to (count of chosenIdx)
			set i to item ci of chosenIdx
			set nm to item ci of chosenNames
			set rowList to {}
			try
				set ts to every track of user playlist i
				repeat with t in ts
					set tn to ""
					set ta to ""
					set tl to ""
					set tp to ""
					try
						set tn to name of t
					end try
					try
						set ta to artist of t
					end try
					try
						set tl to album of t
					end try
					try
						set tp to persistent ID of t
					end try
					set end of rowList to tp & tab & tn & tab & ta & tab & tl
				end repeat
			on error trkErr
				log "  could not read tracks of " & nm & ": " & trkErr
			end try
			set AppleScript's text item delimiters to linefeed
			set body to rowList as text
			set AppleScript's text item delimiters to ""
			set safeName to my sanitize(nm)
			set fpath to outDir & "/" & safeName & ".tsv"
			my writeFile(fpath, "# " & nm & linefeed & "# persistentID" & tab & "title" & tab & "artist" & tab & "album" & linefeed & body & linefeed)
			set end of manifest to nm & tab & (count of rowList) & tab & safeName & ".tsv"
			my progressItem("backed-up", nm, "", ((count of rowList) as text) & " tracks")
		end repeat
	end tell
	set AppleScript's text item delimiters to linefeed
	set m to manifest as text
	set AppleScript's text item delimiters to ""
	my writeFile(outDir & "/MANIFEST.tsv", "# playlist" & tab & "trackCount" & tab & "file" & linefeed & m & linefeed)
	my progressEnd()
	return "Backed up " & (count of manifest) & " playlists to " & outDir
end run

on sanitize(s)
	set r to ""
	repeat with c in (characters of s)
		set cc to c as text
		if cc is "/" or cc is ":" then
			set r to r & "-"
		else
			set r to r & cc
		end if
	end repeat
	return r
end sanitize

on writeFile(p, txt)
	set f to open for access (POSIX file p) with write permission
	set eof f to 0
	write txt to f as «class utf8»
	close access f
end writeFile

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
