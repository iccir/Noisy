set isPlaying to false

if application "Music" is running then
	tell application "Music"
		set isPlaying to get (player state = playing)
	end tell
end if


return isPlaying