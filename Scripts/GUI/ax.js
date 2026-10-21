// Drives the OpenJoystickDriver windows through the Accessibility API of the process
// that runs osascript. System Events is not used: it is a separate process whose
// Accessibility trust is attributed apart from the host app and reports no windows
// when that attribution fails.
// Usage: osascript -l JavaScript ax.js <command> <pid> [argument]
//   probe                      0, or the AXError of reading the app role (-25211: not trusted)
//   app-state                  "main=true|false settings=<tab>|none"
//   current-sidebar            label of the selected sidebar row of the main window
//   select-sidebar <label>     selects that sidebar row
//   wait-main-window           waits for the main window to appear
//   open-settings <tab>        opens Settings from the app menu and selects the tab
//   window-bounds main|settings   "x y width height"
//   close-window main|settings    presses the close button
// The main window is the one with a split group (the sidebar). The Settings window is
// the one without a sidebar whose toolbar holds all three tabs.
ObjC.import("ApplicationServices");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementSetAttributeValue", ["int", ["id", "id", "id"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);

const AX_NOT_TRUSTED = -25211;
const SETTINGS_TABS = ["General", "Notifications", "Advanced"];
const POLL_STEPS = 50;
const POLL_SECONDS = 0.1;
const SETTLE_SECONDS = 0.5;

function read(element, name) {
	const out = Ref();
	const code = $.AXUIElementCopyAttributeValue(element, name, out);
	return { code, value: code === 0 ? out[0] : null };
}

function attribute(element, name) {
	const { value } = read(element, name);
	return value === null ? null : ObjC.unwrap(value);
}

function items(element, name) {
	const { value } = read(element, name);
	if (value === null) return [];
	const result = [];
	for (let index = 0; index < value.count; index++) {
		result.push(value.objectAtIndex(index));
	}
	return result;
}

function children(element, role) {
	return items(element, "AXChildren").filter((child) => attribute(child, "AXRole") === role);
}

function label(element) {
	return attribute(element, "AXTitle") || attribute(element, "AXDescription");
}

function press(element) {
	const code = $.AXUIElementPerformAction(element, "AXPress");
	if (code !== 0) throw new Error("AXPress failed with AXError " + code);
}

function windows(app) {
	return items(app, "AXWindows");
}

function isMain(window) {
	return children(window, "AXSplitGroup").length > 0;
}

function isSettings(window) {
	if (isMain(window)) return false;
	const toolbars = children(window, "AXToolbar");
	if (toolbars.length === 0) return false;
	const buttons = children(toolbars[0], "AXButton").map(label);
	return SETTINGS_TABS.every((tab) => buttons.includes(tab));
}

function find(app, kind) {
	const match = kind === "main" ? isMain : isSettings;
	const found = windows(app).find(match);
	if (!found) throw new Error("no " + kind + " window is open");
	return found;
}

function sidebar(app) {
	const split = children(find(app, "main"), "AXSplitGroup")[0];
	const group = children(split, "AXGroup")[0];
	const scroll = group && children(group, "AXScrollArea")[0];
	const outline = scroll && children(scroll, "AXOutline")[0];
	if (!outline) throw new Error("the main window has no sidebar outline");
	return items(outline, "AXRows");
}

function rowLabel(row) {
	const cell = items(row, "AXChildren")[0];
	const text = cell && children(cell, "AXStaticText")[0];
	return text ? attribute(text, "AXValue") : null;
}

function pair(element, name, first, second) {
	const { value } = read(element, name);
	const found = value && String(value.description).match(
		new RegExp(first + ":(-?[0-9.]+) " + second + ":(-?[0-9.]+)"),
	);
	if (!found) throw new Error("the window reports no " + name);
	return [Math.round(Number(found[1])), Math.round(Number(found[2]))];
}

function waitFor(condition) {
	for (let step = 0; step < POLL_STEPS; step++) {
		const result = condition();
		if (result) return result;
		delay(POLL_SECONDS);
	}
	return null;
}

function run(argv) {
	const [command, pidText, argument] = argv;
	const pid = Number(pidText);
	if (command === "probe") {
		if (!$.AXIsProcessTrusted()) return String(AX_NOT_TRUSTED);
		return String(read($.AXUIElementCreateApplication(pid), "AXRole").code);
	}
	const app = $.AXUIElementCreateApplication(pid);
	switch (command) {
		case "app-state": {
			const all = windows(app);
			const settings = all.find(isSettings);
			return (
				"main=" + all.some(isMain) + " settings=" + (settings ? attribute(settings, "AXTitle") : "none")
			);
		}
		case "current-sidebar": {
			const row = sidebar(app).find((candidate) => attribute(candidate, "AXSelected"));
			if (!row) throw new Error("no sidebar row is selected");
			return rowLabel(row);
		}
		case "select-sidebar": {
			const row = sidebar(app).find((candidate) => rowLabel(candidate) === argument);
			if (!row) throw new Error("no sidebar item named " + argument);
			const code = $.AXUIElementSetAttributeValue(row, "AXSelected", $.kCFBooleanTrue);
			if (code !== 0) throw new Error("selecting " + argument + " failed with AXError " + code);
			delay(SETTLE_SECONDS);
			return "";
		}
		case "wait-main-window":
			if (!waitFor(() => windows(app).some(isMain))) throw new Error("main window did not appear");
			return "";
		case "open-settings": {
			$.AXUIElementSetAttributeValue(app, "AXFrontmost", $.kCFBooleanTrue);
			const menuBar = children(app, "AXMenuBar")[0];
			const appMenu = menuBar && children(menuBar, "AXMenuBarItem").find((item) => label(item) === "OpenJoystickDriver");
			const menu = appMenu && children(appMenu, "AXMenu")[0];
			const entry = menu && children(menu, "AXMenuItem").find((item) => label(item) === "Settings...");
			if (!entry) throw new Error("the app menu has no Settings... item");
			press(entry);
			const window = waitFor(() => windows(app).find(isSettings));
			const tab = window && children(children(window, "AXToolbar")[0], "AXButton").find((button) => label(button) === argument);
			if (!tab) throw new Error("no Settings window with a tab named " + argument);
			press(tab);
			delay(SETTLE_SECONDS);
			return "";
		}
		case "window-bounds": {
			const window = find(app, argument);
			return pair(window, "AXPosition", "x", "y").concat(pair(window, "AXSize", "w", "h")).join(" ");
		}
		case "close-window": {
			const { value: button } = read(find(app, argument), "AXCloseButton");
			if (button === null) throw new Error("the " + argument + " window has no close button");
			press(button);
			return "";
		}
		default:
			throw new Error("unknown command " + command);
	}
}
