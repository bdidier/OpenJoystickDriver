-- Prints the label of the selected sidebar row of the main window.
-- Usage: osascript current-sidebar.applescript
on run
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			if exists (splitter group 1 of w) then
				set sidebar to outline 1 of scroll area 1 of group 1 of splitter group 1 of w
				repeat with r in rows of sidebar
					if selected of r then return value of static text 1 of UI element 1 of r
				end repeat
				error "no sidebar row is selected"
			end if
		end repeat
		error "main window is not open"
	end tell
end run
