// Prints the on-screen windows of every process, front to back, as JSON:
// [{id, pid, owner, layer, x, y, width, height}].
// Usage: osascript -l JavaScript window-list.js
ObjC.import("CoreGraphics");
function run() {
	const info = ObjC.deepUnwrap(
		ObjC.castRefToObject(
			$.CGWindowListCopyWindowInfo(
				$.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements,
				$.kCGNullWindowID,
			),
		),
	);
	return JSON.stringify(
		info.map((w) => ({
			id: w.kCGWindowNumber,
			pid: w.kCGWindowOwnerPID,
			owner: w.kCGWindowOwnerName || "",
			layer: w.kCGWindowLayer,
			x: w.kCGWindowBounds.X,
			y: w.kCGWindowBounds.Y,
			width: w.kCGWindowBounds.Width,
			height: w.kCGWindowBounds.Height,
		})),
	);
}
