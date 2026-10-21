-- Opens the main window of the installed app and waits until it exists.
-- Usage: osascript open-main-window.applescript
on run
	do shell script "open -b com.openjoystickdriver"
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat 50 times
			repeat with w in windows
				if exists (splitter group 1 of w) then return
			end repeat
			delay 0.1
		end repeat
	end tell
	error "main window did not appear"
end run
