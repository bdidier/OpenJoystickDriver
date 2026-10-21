-- Closes every window of the app with its close button.
-- Usage: osascript close-windows.applescript
on run
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat while (count of windows) > 0
			set n to count of windows
			click button 1 of window 1
			delay 0.3
			if (count of windows) is n then error "a window did not close"
		end repeat
	end tell
end run
