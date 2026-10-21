-- Selects a sidebar row of the main window by its label through Accessibility.
-- Usage: osascript select-sidebar.applescript Controllers|Profiles|Library|Access|Activity
on run argv
	set label to item 1 of argv
	tell application "System Events" to tell process "OpenJoystickDriver"
		repeat with w in windows
			if exists (splitter group 1 of w) then
				set sidebar to outline 1 of scroll area 1 of group 1 of splitter group 1 of w
				repeat with r in rows of sidebar
					if (value of static text 1 of UI element 1 of r) is label then
						set selected of r to true
						delay 0.5
						return
					end if
				end repeat
				error "no sidebar item named " & label
			end if
		end repeat
		error "main window is not open"
	end tell
end run
