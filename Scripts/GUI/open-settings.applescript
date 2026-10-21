-- Opens Settings from the app menu and selects a tab through Accessibility.
-- Usage: osascript open-settings.applescript General|Notifications|Advanced
on run argv
	set label to item 1 of argv
	tell application "System Events" to tell process "OpenJoystickDriver"
		set frontmost to true
		click menu item "Settings..." of menu "OpenJoystickDriver" of menu bar 1
		repeat 50 times
			repeat with w in windows
				if exists (button label of toolbar 1 of w) then
					click button label of toolbar 1 of w
					delay 0.5
					return
				end if
			end repeat
			delay 0.1
		end repeat
		error "no Settings tab named " & label
	end tell
end run
