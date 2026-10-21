-- Closes the Settings window with its close button, found by subrole.
-- The Settings window is the one without a sidebar whose toolbar holds all three tabs.
-- Usage: osascript close-settings.applescript
on run
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			if my isSettings(w) then
				click (first button of w whose subrole is "AXCloseButton")
				return
			end if
		end repeat
	end tell
	error "no Settings window is open"
end run

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
