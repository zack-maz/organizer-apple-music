#!/usr/bin/osascript
--
-- build-genres.applescript
--
-- Builds the whole genre library in ONE creation pass: every playlist is made
-- directly inside its parent folder, already lowercase, already filled.
--
-- Why one pass: iCloud sync reverts modifications to existing synced objects
-- (renames, moves, row deletions) while letting creations stand, because new
-- objects carry new IDs and cannot conflict. Building the final shape up front
-- leaves sync nothing to undo. This replaces the old
-- organize-by-genre -> group-genres -> lowercase-names pipeline, whose last two
-- steps were exactly the post-hoc edits that kept getting reverted.
--
-- Genres are folded to lowercase and uniqued case-insensitively, so "Hip-Hop"
-- and "hip-hop" become one `hip-hop` playlist rather than two competing ones.
-- Nothing is merged beyond case: `hip-hop`, `rap` and `hip-hop/rap` stay
-- separate playlists that share a parent folder.
--
-- Two modes, chosen by whether the folder already exists:
--   * no folder, or --replace: the full build described above (--replace
--     deletes the existing folder first).
--   * folder exists, no --replace: incremental. Only tracks not yet in any
--     genre playlist are touched -- they are appended to their genre's existing
--     playlist, and a genre with no playlist yet gets one created in full,
--     inside its parent folder. Nothing existing is renamed, moved or removed.
--     Appending rows to a synced playlist is still a modification, and whether
--     sync keeps those rows is not established; --replace remains the sure path.
--
-- Usage:
--   ./build-genres.applescript [--dry-run] [--replace] [--folder NAME] [--min-tracks N] [--progress]
--
--   --progress  Emit one machine-readable line per track filed on stderr (see
--               the progress handlers at the end of the file). Used by the app.
--

use AppleScript version "2.4"
use framework "Foundation"
use scripting additions

property defaultFolderName : "genres"
property unknownName : "unknown genre"
-- --progress state; see the progress handlers at the end of the file
property progressOn : false
property progressDone : 0
property progressTotal : 0

-- {parent folder, {genres it holds}} -- all lowercase, matched case-insensitively
property groups : {¬
	{"hip-hop & rap", {"hip-hop/rap", "hip-hop", "rap", "alternative rap", "uk hip-hop", "latin rap", "dirty south"}}, ¬
	{"rock & alternative", {"alternative", "rock", "hard rock", "indie rock", "blues-rock", "punk", "hardcore", "metal", "psychedelic", "surf", "rock y alternativo"}}, ¬
	{"electronic & dance", {"electronic", "electronica", "dance", "house", "techno", "trance", "downtempo", "idm/experimental", "jungle/drum'n'bass"}}, ¬
	{"pop", {"pop", "vocal pop", "indie pop", "french pop", "j-pop", "mandopop", "vocal"}}, ¬
	{"r&b, soul & funk", {"r&b/soul", "soul", "neo-soul", "motown", "funk"}}, ¬
	{"jazz & blues", {"jazz", "crossover jazz", "latin jazz", "blues"}}, ¬
	{"folk, country & songwriter", {"country", "honky tonk", "folk", "alternative folk", "folk-rock", "singer/songwriter"}}, ¬
	{"reggae & caribbean", {"reggae", "roots reggae", "dub", "lovers rock", "modern dancehall"}}, ¬
	{"latin & brazilian", {"latin", "pop latino", "urbano latino", "música mexicana", "música tropical", "brazilian", "mpb", "samba", "baile funk"}}, ¬
	{"global & world", {"african", "afrobeats", "afro house", "amapiano", "arabic pop", "maghreb rai", "farsi", "indian", "telugu", "worldwide"}}, ¬
	{"ambient & instrumental", {"ambient", "new age", "instrumental", "easy listening"}}, ¬
	{"soundtracks & screen", {"soundtrack", "original score", "anime"}}, ¬
	{"other", {"unknown genre", "christian", "comedy", "modern era"}}}

on run argv
	set folderName to defaultFolderName
	set dryRun to false
	set replaceExisting to false
	set minTracks to 1

	set i to 1
	repeat while i ≤ (count of argv)
		set a to item i of argv
		if a is "--dry-run" then
			set dryRun to true
		else if a is "--replace" then
			set replaceExisting to true
		else if a is "--folder" then
			set i to i + 1
			if i > (count of argv) then error "--folder needs a value."
			set folderName to item i of argv
		else if a is "--min-tracks" then
			set i to i + 1
			if i > (count of argv) then error "--min-tracks needs a value."
			set minTracks to (item i of argv) as integer
		else if a is "--progress" then
			set progressOn to true
		else if a is "-h" or a is "--help" then
			return "Usage: build-genres.applescript [--dry-run] [--replace] [--folder NAME] [--min-tracks N] [--progress]"
		else
			error "Unknown option: " & a
		end if
		set i to i + 1
	end repeat

	log "Reading library..."
	tell application "Music"
		if it is not running then launch
		set lib to library playlist 1
		with timeout of 3600 seconds
			set rawGenres to genre of every track of lib
			set idList to persistent ID of every track of lib
		end timeout
		set treeExists to exists folder playlist folderName
	end tell
	set libTotal to count of rawGenres
	if libTotal is 0 then return "No tracks in the library."

	-- fold to lowercase up front: the playlist name IS the lowercased genre,
	-- so there is never a rename step
	set folded to {}
	repeat with g in rawGenres
		set gv to contents of g
		if gv is missing value then
			set end of folded to unknownName
		else if (gv as text) is "" then
			set end of folded to unknownName
		else
			set end of folded to ((current application's NSString's stringWithString:(gv as text))'s lowercaseString()) as text
		end if
	end repeat

	set uniqueSet to current application's NSOrderedSet's orderedSetWithArray:folded
	set allGenres to (uniqueSet's array()'s sortedArrayUsingSelector:"localizedStandardCompare:") as list
	set tally to current application's NSCountedSet's setWithArray:folded
	log ((count of allGenres) as text) & " genres across " & (libTotal as text) & " tracks."

	-- an existing folder without --replace means: keep it, file only what is new
	if treeExists and not replaceExisting then return my addNew(folderName, dryRun, minTracks, folded, idList, tally)

	-- assign each genre to a parent folder; anything unlisted is reported
	set claimed to {}
	repeat with grp in groups
		repeat with m in (item 2 of grp)
			set end of claimed to (m as text)
		end repeat
	end repeat
	set strays to {}
	repeat with g in allGenres
		set gs to g as text
		set isKnown to false
		repeat with c in claimed
			considering case
				if (c as text) is gs then set isKnown to true
			end considering
		end repeat
		if not isKnown then set end of strays to gs
	end repeat

	set report to {}
	set plannedFolders to 0
	set plannedLists to 0
	set plannedTracks to 0
	set strayTracks to 0

	repeat with grp in groups
		set gname to item 1 of grp
		set present to {}
		repeat with m in (item 2 of grp)
			set ms to m as text
			set n to (tally's countForObject:ms) as integer
			if n ≥ minTracks and n > 0 then set end of present to {ms, n}
		end repeat
		if (count of present) > 0 then
			set plannedFolders to plannedFolders + 1
			set end of report to gname
			repeat with pr in present
				set plannedLists to plannedLists + 1
				set plannedTracks to plannedTracks + (item 2 of pr)
				set end of report to "    " & (item 1 of pr) & "  (" & (item 2 of pr) & ")"
			end repeat
		end if
	end repeat

	if (count of strays) > 0 then
		set end of report to ""
		set end of report to "UNMAPPED - will be created at the top of \"" & folderName & "\" (" & (count of strays) & "):"
		repeat with sgen in strays
			set sg to sgen as text
			set end of report to "    " & sg & "  (" & ((tally's countForObject:sg) as integer) & ")"
			if ((tally's countForObject:sg) as integer) ≥ minTracks then set strayTracks to strayTracks + ((tally's countForObject:sg) as integer)
		end repeat
		set end of report to "  Add them to the `groups` table and re-run to file them."
	end if

	if dryRun then
		set end of report to ""
		set end of report to "DRY RUN - would create " & plannedFolders & " folders, " & plannedLists & " playlists, " & plannedTracks & " track entries."
		return my joinUp(report)
	end if

	my progressBegin(plannedTracks + strayTracks, "tracks")

	-- create everything, in final form
	tell application "Music"
		if treeExists then
			log "Deleting existing \"" & folderName & "\"..."
			delete folder playlist folderName
		end if
		set rootFolder to make new folder playlist with properties {name:folderName}
	end tell

	set madeLists to 0
	set copied to 0

	repeat with grp in groups
		set gname to item 1 of grp
		set present to {}
		repeat with m in (item 2 of grp)
			set ms to m as text
			set n to (tally's countForObject:ms) as integer
			if n ≥ minTracks and n > 0 then set end of present to ms
		end repeat

		if (count of present) > 0 then
			tell application "Music"
				set subFolder to make new folder playlist at rootFolder with properties {name:gname}
			end tell
			log "  " & gname
			repeat with gs in present
				set thisGenre to gs as text
				set got to my fillOne(thisGenre, subFolder, thisGenre)
				if got > 0 then set madeLists to madeLists + 1
				set copied to copied + got
			end repeat
		end if
	end repeat

	-- unmapped genres land at the root so they are visible, not buried
	repeat with sgen in strays
		set sg to sgen as text
		set n to (tally's countForObject:sg) as integer
		if n ≥ minTracks then
			set got to my fillOne(sg, rootFolder, sg)
			if got > 0 then set madeLists to madeLists + 1
			set copied to copied + got
			log "  (unmapped) " & sg
		end if
	end repeat

	my progressEnd()
	set end of report to ""
	set end of report to "Created " & madeLists & " playlists holding " & copied & " tracks in \"" & folderName & "\"."
	return my joinUp(report)
end run

-- Incremental pass over an existing tree: files only the tracks not yet in
-- any genre playlist. A genre that already has a playlist gets its new tracks
-- appended; a genre with no playlist yet is created in full, inside its parent
-- folder, exactly as the full build would make it. Nothing existing is
-- renamed, moved or removed.
on addNew(folderName, dryRun, minTracks, folded, idList, tally)
	-- what the tree holds now: every filed persistent ID, plus the name and
	-- index of each playlist under the folder (its own children or a parent's)
	set filed to current application's NSMutableSet's alloc()'s init()
	set haveNames to {}
	set haveIdx to {}
	tell application "Music"
		with timeout of 3600 seconds
			repeat with pi from 1 to (count of user playlists)
				try
					set inScope to ((name of parent of user playlist pi) is folderName)
					if not inScope then
						try
							if (name of parent of parent of user playlist pi) is folderName then set inScope to true
						end try
					end if
					if inScope then
						set end of haveNames to (name of user playlist pi) as text
						set end of haveIdx to pi
						filed's addObjectsFromArray:(persistent ID of every track of user playlist pi)
					end if
				end try
			end repeat
		end timeout
	end tell

	-- library minus tree = the new tracks, bucketed by folded genre. Each
	-- bucket holds library indexes, so --progress can name a track from the
	-- bulk reads without a call per track.
	set newGenres to {}
	set newRows to {}
	repeat with k from 1 to (count of idList)
		set pid to (item k of idList) as text
		if not ((filed's containsObject:pid) as boolean) then
			set g to item k of folded
			set slot to my indexOf(g, newGenres)
			if slot is 0 then
				set end of newGenres to g
				set end of newRows to {k}
			else
				set item slot of newRows to (item slot of newRows) & {k}
			end if
		end if
	end repeat

	set report to {}
	set end of report to "Existing \"" & folderName & "\" kept: " & ((filed's |count|()) as integer) & " tracks already filed in " & (count of haveNames) & " playlists (pass --replace to rebuild)."
	if (count of newGenres) is 0 then
		set end of report to "Everything in the library is already filed. Nothing to do."
		return my joinUp(report)
	end if

	-- plan: append where a playlist exists, create where none does
	set addPlan to {}
	set makePlan to {}
	set skipped to {}
	set newTotal to 0
	set plannedTotal to 0
	repeat with gi from 1 to (count of newGenres)
		set g to item gi of newGenres
		set ids to item gi of newRows
		set newTotal to newTotal + (count of ids)
		set slot to my indexOf(g, haveNames)
		if slot > 0 then
			set end of addPlan to {g, ids, item slot of haveIdx}
			set plannedTotal to plannedTotal + (count of ids)
		else if ((tally's countForObject:g) as integer) < minTracks then
			set end of skipped to g
		else
			set end of makePlan to {g, my parentOf(g)}
			set plannedTotal to plannedTotal + ((tally's countForObject:g) as integer)
		end if
	end repeat

	set end of report to (newTotal as text) & " new track(s) since the last build."
	if (count of addPlan) > 0 then
		set end of report to ""
		set end of report to "Into existing playlists:"
		repeat with ap in addPlan
			set end of report to "    " & (item 1 of ap) & "  (+" & (count of (item 2 of ap)) & ")"
		end repeat
	end if
	if (count of makePlan) > 0 then
		set end of report to ""
		set end of report to "New genres - playlist created in full:"
		repeat with mp in makePlan
			set g to item 1 of mp
			-- NB: not `where` -- that is a synonym for `whose` in Music's dictionary
			set placeAt to item 2 of mp
			if placeAt is "" then set placeAt to "(unmapped, top of \"" & folderName & "\")"
			set end of report to "    " & placeAt & " / " & g & "  (" & ((tally's countForObject:g) as integer) & ")"
		end repeat
	end if
	if (count of skipped) > 0 then
		set end of report to ""
		set end of report to "Skipped, fewer than " & minTracks & " tracks: " & my joinWith(skipped, ", ")
	end if

	if dryRun then
		set end of report to ""
		set end of report to "DRY RUN - would add to " & (count of addPlan) & " playlists and create " & (count of makePlan) & " playlists. Nothing changed."
		return my joinUp(report)
	end if

	-- append first, while the playlist indexes gathered above are still valid;
	-- creating playlists afterwards cannot disturb them
	-- with --progress, names for the feed come from one bulk read of the
	-- library, never from a call per track
	set titleList to {}
	set whoList to {}
	if progressOn and (count of addPlan) > 0 then
		tell application "Music"
			with timeout of 3600 seconds
				set titleList to name of every track of library playlist 1
				set whoList to artist of every track of library playlist 1
			end timeout
		end tell
	end if
	my progressBegin(plannedTotal, "tracks")

	set added to 0
	tell application "Music"
		set lib to library playlist 1
		with timeout of 3600 seconds
			repeat with ap in addPlan
				set idx to item 3 of ap
				set p to user playlist idx
				repeat with rowRef in (item 2 of ap)
					set k to contents of rowRef
					set pid to (item k of idList) as text
					try
						duplicate (every track of lib whose persistent ID is pid) to p
						set added to added + 1
						my progressItem("added", item 1 of ap, my progressAt(whoList, k), my progressAt(titleList, k))
					on error e
						log "    could not add to " & (item 1 of ap) & ": " & e
					end try
				end repeat
				log "  " & (item 1 of ap) & "  +" & (count of (item 2 of ap))
			end repeat
		end timeout
	end tell

	set madeLists to 0
	set copied to 0
	repeat with mp in makePlan
		set g to item 1 of mp
		set parentName to item 2 of mp
		if parentName is "" then
			tell application "Music" to set intoFolder to folder playlist folderName
			log "  (unmapped) " & g
		else
			set intoFolder to my subFolderOf(parentName, folderName)
			log "  " & parentName & " / " & g
		end if
		set got to my fillOne(g, intoFolder, g)
		if got > 0 then set madeLists to madeLists + 1
		set copied to copied + got
	end repeat

	my progressEnd()
	set end of report to ""
	set end of report to "Added " & added & " tracks to " & (count of addPlan) & " playlists; created " & madeLists & " playlists holding " & copied & " tracks."
	return my joinUp(report)
end addNew

-- 1-based position of `needle` in `haystack`, or 0. Case-insensitive on
-- purpose: an older title-case playlist should receive its genre's new tracks
-- rather than gain a lowercase twin.
on indexOf(needle, haystack)
	repeat with k from 1 to (count of haystack)
		if (item k of haystack) is needle then return k
	end repeat
	return 0
end indexOf

-- The parent folder name for a genre from the `groups` table, or "" if it is
-- not listed and belongs at the top of the genre folder.
on parentOf(genreName)
	repeat with grp in groups
		repeat with m in (item 2 of grp)
			if (m as text) is genreName then return item 1 of grp
		end repeat
	end repeat
	return ""
end parentOf

-- The parent folder named `parentName` inside the genre folder, created if
-- this is the first genre of its group in the library. A folder cannot
-- enumerate its own children, so every folder playlist is checked by parent.
on subFolderOf(parentName, folderName)
	tell application "Music"
		repeat with fi from 1 to (count of folder playlists)
			try
				if ((name of folder playlist fi) is parentName) and ((name of parent of folder playlist fi) is folderName) then return folder playlist fi
			end try
		end repeat
		return make new folder playlist at (folder playlist folderName) with properties {name:parentName}
	end tell
end subFolderOf

on joinWith(lst, sep)
	set AppleScript's text item delimiters to sep
	set outText to lst as text
	set AppleScript's text item delimiters to ""
	return outText
end joinWith

-- Makes the playlist inside `intoFolder`, already named, then fills it.
-- NB: do not name this parameter `container` -- that is a term in Music's
-- dictionary, and `at container` binds to the term, not the variable, failing
-- with -2710 "Can't make class user playlist".
on fillOne(genreName, intoFolder, plName)
	-- Tracks with no genre are *displayed* as "unknown genre" but must be
	-- *filtered* on the empty string -- no track carries the placeholder as its
	-- actual genre, so filtering on it matches nothing and the playlist is lost.
	set filterVal to genreName
	if genreName is unknownName then set filterVal to ""
	tell application "Music"
		set lib to library playlist 1
		set p to make new user playlist at intoFolder with properties {name:plName}
		with timeout of 3600 seconds
			try
				-- the `whose` clause must be restated inline; a stored result
				-- becomes a resolved list and duplicate rejects it
				duplicate (every track of lib whose genre is filterVal) to p
			on error e
				log "    could not fill " & plName & ": " & e
			end try
		end timeout
		set landed to count of tracks of p
		if landed is 0 then delete p
		if landed > 0 and progressOn then
			-- the fill stays one bulk duplicate; the feed gets one bulk read of
			-- names per playlist, so songs land playlist by playlist
			with timeout of 3600 seconds
				set titleList to name of every track of p
				set whoList to artist of every track of p
			end timeout
			my progressMark("created", plName, (landed as text) & " tracks")
			repeat with k from 1 to (count of titleList)
				my progressItem("added", plName, my progressAt(whoList, k), item k of titleList)
			end repeat
		end if
	end tell
	return landed
end fillOne

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
