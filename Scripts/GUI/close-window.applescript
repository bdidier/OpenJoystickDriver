-- Closes the main or Settings window with its close button, found by subrole.
-- The Settings window is the one without a sidebar whose toolbar holds all three tabs.
-- Usage: osascript close-window.applescript main|settings
on run argv
	set windowKind to item 1 of argv
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			set isMain to exists (splitter group 1 of w)
			if (windowKind is "main" and isMain) or (windowKind is "settings" and my isSettings(w)) then
				click (first button of w whose subrole is "AXCloseButton")
				return
			end if
		end repeat
	end tell
	error "no " & windowKind & " window is open"
end run

-- Same predicate as in open-settings.applescript, window-bounds.applescript, app-state.applescript: osascript has no imports, keep every copy equal.
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
