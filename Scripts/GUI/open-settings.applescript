-- Opens Settings from the app menu and selects a tab through Accessibility.
-- The Settings window is the one without a sidebar whose toolbar holds all three tabs.
-- Usage: osascript open-settings.applescript General|Notifications|Advanced
on run argv
	set label to item 1 of argv
	tell application "System Events" to tell process "OpenJoystickDriver"
		set frontmost to true
		click menu item "Settings..." of menu "OpenJoystickDriver" of menu bar 1
		repeat 50 times
			repeat with w in windows
				if my isSettings(w) then
					click button label of toolbar 1 of w
					delay 0.5
					return
				end if
			end repeat
			delay 0.1
		end repeat
		error "no Settings window with a tab named " & label
	end tell
end run

-- Same predicate as in window-bounds.applescript, close-window.applescript, app-state.applescript: osascript has no imports, keep every copy equal.
on isSettings(w)
	tell application "System Events" to tell process "OpenJoystickDriver"
		if exists (splitter group 1 of w) then return false
		if not (exists (toolbar 1 of w)) then return false
		repeat with tabLabel in {"General", "Notifications", "Advanced"}
			if not (exists (button tabLabel of toolbar 1 of w)) then return false
		end repeat
		return true
	end tell
end isSettings
