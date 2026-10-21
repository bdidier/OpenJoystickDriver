// Prints the on-screen windows of a process as JSON: [{id, x, y, width, height}].
// Usage: osascript -l JavaScript window-list.js <pid>
ObjC.import("CoreGraphics");
function run(argv) {
	const pid = Number(argv[0]);
	const info = ObjC.deepUnwrap(
		ObjC.castRefToObject(
			$.CGWindowListCopyWindowInfo(
				$.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements,
				$.kCGNullWindowID,
			),
		),
	);
	return JSON.stringify(
		info
			.filter((w) => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0)
			.map((w) => ({
				id: w.kCGWindowNumber,
				x: w.kCGWindowBounds.X,
				y: w.kCGWindowBounds.Y,
				width: w.kCGWindowBounds.Width,
				height: w.kCGWindowBounds.Height,
			})),
	);
}
