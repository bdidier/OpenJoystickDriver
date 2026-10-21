-- Prints "main=true|false settings=<tab>|none": whether the main window is open and which
-- tab the open Settings window shows (the window title is the tab name).
-- The Settings window is the one without a sidebar whose toolbar holds all three tabs.
-- Usage: osascript app-state.applescript
on run
	set mainOpen to "false"
	set settingsTab to "none"
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			if exists (splitter group 1 of w) then
				set mainOpen to "true"
			else if my isSettings(w) then
				set settingsTab to name of w
			end if
		end repeat
	end tell
	return "main=" & mainOpen & " settings=" & settingsTab
end run

-- Same predicate as in open-settings.applescript, window-bounds.applescript, close-window.applescript: osascript has no imports, keep every copy equal.
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
