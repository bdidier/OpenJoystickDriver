-- Prints "x y width height" of the main or Settings window.
-- Usage: osascript window-bounds.applescript main|settings
on run argv
	set windowKind to item 1 of argv
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			set isMain to exists (splitter group 1 of w)
			if (windowKind is "main" and isMain) or (windowKind is "settings" and not isMain and exists (toolbar 1 of w)) then
				set {x, y} to position of w
				set {wd, ht} to size of w
				return (x as text) & " " & (y as text) & " " & (wd as text) & " " & (ht as text)
			end if
		end repeat
	end tell
	error "no " & windowKind & " window is open"
end run
