// Prints the AXError code of reading the focused application from the system-wide
// accessibility element, the call System Events UI scripting depends on.
// 0 means the controlling process may use UI scripting; -25211 means Accessibility
// is not granted to it.
// Usage: osascript -l JavaScript accessibility-probe.js
ObjC.import("ApplicationServices");
function run() {
	const focused = Ref();
	return String(
		$.AXUIElementCopyAttributeValue(
			$.AXUIElementCreateSystemWide(),
			$("AXFocusedApplication"),
			focused,
		),
	);
}
