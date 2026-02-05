set isPlaying to false

if application "Swinsian" is running then
	tell application "Swinsian"
		set isPlaying to get (player state = playing)
	end tell
end if


return isPlaying