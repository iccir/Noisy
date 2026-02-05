set isPlaying to false

if application "Spotify" is running then
	tell application "Spotify"
		set isPlaying to get (player state = playing)
	end tell
end if


return isPlaying
