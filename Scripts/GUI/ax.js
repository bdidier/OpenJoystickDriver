// Drives the OpenJoystickDriver windows through the Accessibility API of the process
// that runs osascript. System Events is not used: it is a separate process whose
// Accessibility trust is attributed apart from the host app and reports no windows
// when that attribution fails.
// Usage: osascript -l JavaScript ax.js <command> <pid> [argument...]
//   session                    "locked=true|false console=true|false" (no pid needed)
//   probe                      0, or the AXError of reading the app role (-25211: not trusted)
//   app-state                  "main=true|false settings=<tab>|none"
//   current-sidebar            label of the selected sidebar row of the main window
//   select-sidebar <label>     selects that sidebar row
//   wait-main-window           waits for the main window to appear
//   open-settings <tab>        opens Settings from the app menu and selects the tab
//   window-bounds main|settings   "x y width height"
//   close-window main|settings    presses the close button
//   activate                   makes the app frontmost (AXFrontmost and NSRunningApplication)
//   raise main|settings        activates the app and raises that window (AXRaise)
//   menu-titles                titles of the main menu bar items, one per line, in menu bar order
//   open-menu <title> [item...]   activates the app, opens that main menu bar item and presses
//                              each named item in turn, which opens a submenu
//   open-status-menu [item...] the same for the app's status item (AXExtrasMenuBar)
//   press-escape               posts an Escape key press to the frontmost app, which closes
//                              the innermost open menu
// The main window is the one with a split group (the sidebar). The Settings window is
// the one without a sidebar whose toolbar holds all three tabs.
ObjC.import("ApplicationServices");
ObjC.import("CoreGraphics");
ObjC.import("AppKit");
ObjC.bindFunction("AXUIElementCreateApplication", ["id", ["int"]]);
ObjC.bindFunction("AXUIElementCopyAttributeValue", ["int", ["id", "id", "id *"]]);
ObjC.bindFunction("AXUIElementSetAttributeValue", ["int", ["id", "id", "id"]]);
ObjC.bindFunction("AXUIElementSetMessagingTimeout", ["int", ["id", "float"]]);
ObjC.bindFunction("AXUIElementPerformAction", ["int", ["id", "id"]]);

const AX_NOT_TRUSTED = -25211;
// NSApplicationActivateAllWindows: brings every window of the app forward, not only the key one.
const ACTIVATE_ALL_WINDOWS = 1;
// Virtual key code of Escape.
const KEY_ESCAPE = 53;
// $.kCFBooleanTrue is a pointer to the constant, which AX rejects as a value (AXError -25201); a boxed NSNumber bool bridges to a CFBoolean.
const AX_TRUE = $.NSNumber.numberWithBool(true);
const SETTINGS_TABS = ["General", "Notifications", "Advanced"];
const POLL_STEPS = 50;
const POLL_SECONDS = 0.1;
const SETTLE_SECONDS = 0.5;
// AXError codes that mean the element holds no such attribute.
const AX_ATTRIBUTE_ABSENT = [-25205, -25212];
// AXError codes that mean the state is not settled yet: -25204 the app is busy, -25202 a
// window was torn down between two reads. Waits treat them as "not yet".
const AX_TRANSIENT = [-25204, -25202];
// An app that does not answer blocks an AX call for the default timeout of about 6 s,
// which would overrun the readiness deadline of capture.py; the probe gives up sooner.
const PROBE_MESSAGING_TIMEOUT_SECONDS = 1;

function readCode(element, name) {
	const out = Ref();
	const code = $.AXUIElementCopyAttributeValue(element, name, out);
	return { code, value: code === 0 ? out[0] : null };
}

// "ok" for 0, "absent" for a missing attribute, "transient" for a state that can settle,
// "error" for everything else.
function classifyAxCode(code) {
	if (code === 0) return "ok";
	if (AX_ATTRIBUTE_ABSENT.includes(code)) return "absent";
	if (AX_TRANSIENT.includes(code)) return "transient";
	return "error";
}

function read(element, name) {
	const result = readCode(element, name);
	const kind = classifyAxCode(result.code);
	if (kind === "error" || kind === "transient") {
		const error = new Error("reading " + name + " failed with AXError " + result.code);
		error.axCode = result.code;
		throw error;
	}
	return result;
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

// Makes the app frontmost through the Accessibility API and NSRunningApplication. The return
// value of activateWithOptions is not read: whether the app came forward is decided by the
// window list, which capture.py reads and refuses on.
function activate(app, pid) {
	const code = $.AXUIElementSetAttributeValue(app, "AXFrontmost", AX_TRUE);
	if (code !== 0) throw new Error("bringing the app to the front failed with AXError " + code);
	$.NSRunningApplication.runningApplicationWithProcessIdentifier(pid).activateWithOptions(ACTIVATE_ALL_WINDOWS);
}

function mainMenuBar(app) {
	const bar = children(app, "AXMenuBar")[0];
	if (!bar) throw new Error("the app has no menu bar");
	return bar;
}

function statusMenuBarItem(app) {
	const { value: bar } = read(app, "AXExtrasMenuBar");
	if (bar === null) throw new Error("the app has no status item menu bar");
	const found = children(bar, "AXMenuBarItem");
	if (found.length !== 1) throw new Error("the app has " + found.length + " status items, expected 1");
	return found[0];
}

// Presses each named item of the menu that belongs to `start`, so a submenu opens.
function pressPath(start, names) {
	let element = start;
	for (const name of names) {
		const entry = waitFor(() => {
			const menu = children(element, "AXMenu")[0];
			return menu && children(menu, "AXMenuItem").find((item) => label(item) === name);
		}, "menu item " + name + " did not appear");
		press(entry);
		element = entry;
	}
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

// AXValueGetValue cannot be called from JXA: the CGPoint and CGSize out-parameters
// need a struct type that bindFunction rejects, so the value is read from its description.
function pair(element, name, first, second) {
	const { value } = read(element, name);
	const found = value && ObjC.unwrap(value.description).match(
		new RegExp(first + ":(-?[0-9.]+) " + second + ":(-?[0-9.]+)"),
	);
	if (!found) throw new Error("the window reports no " + name);
	return [Math.round(Number(found[1])), Math.round(Number(found[2]))];
}

// Polls for the condition. A transient AXError counts as "not yet" because the app
// settles after a launch or a click; it is kept and named when the steps run out.
// Any other error ends the wait at once.
function waitFor(condition, what) {
	let last = null;
	for (let step = 0; step < POLL_STEPS; step++) {
		try {
			const result = condition();
			if (result) return result;
		} catch (error) {
			if (error.axCode === undefined || classifyAxCode(error.axCode) !== "transient") throw error;
			last = error.axCode;
		}
		delay(POLL_SECONDS);
	}
	throw new Error(
		what + " within " + POLL_STEPS * POLL_SECONDS + " s" + (last === null ? "" : " (last AXError " + last + ")"),
	);
}

function run(argv) {
	const [command, pidText, argument, ...rest] = argv;
	if (command === "session") {
		const dictionary = $.CGSessionCopyCurrentDictionary();
		const session = dictionary && ObjC.deepUnwrap(ObjC.castRefToObject(dictionary));
		if (!session) throw new Error("the process has no window server session");
		return (
			"locked=" + Boolean(session.CGSSessionScreenIsLocked) + " console=" + Boolean(session.kCGSSessionOnConsoleKey)
		);
	}
	const pid = Number(pidText);
	if (command === "probe") {
		if (!$.AXIsProcessTrusted()) return String(AX_NOT_TRUSTED);
		const probed = $.AXUIElementCreateApplication(pid);
		const timeout = $.AXUIElementSetMessagingTimeout(probed, PROBE_MESSAGING_TIMEOUT_SECONDS);
		if (timeout !== 0) throw new Error("setting the probe timeout failed with AXError " + timeout);
		return String(readCode(probed, "AXRole").code);
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
			const name = rowLabel(row);
			if (name === null) throw new Error("the selected sidebar row has no label");
			return name;
		}
		case "select-sidebar": {
			const row = sidebar(app).find((candidate) => rowLabel(candidate) === argument);
			if (!row) throw new Error("no sidebar item named " + argument);
			const code = $.AXUIElementSetAttributeValue(row, "AXSelected", AX_TRUE);
			if (code !== 0) throw new Error("selecting " + argument + " failed with AXError " + code);
			waitFor(() => attribute(row, "AXSelected") === true, "sidebar item " + argument + " did not become selected");
			delay(SETTLE_SECONDS);
			return "";
		}
		case "wait-main-window":
			waitFor(() => windows(app).some(isMain), "main window did not appear");
			return "";
		case "open-settings": {
			const front = $.AXUIElementSetAttributeValue(app, "AXFrontmost", AX_TRUE);
			if (front !== 0) throw new Error("bringing the app to the front failed with AXError " + front);
			const menuBar = children(app, "AXMenuBar")[0];
			const appMenu = menuBar && children(menuBar, "AXMenuBarItem").find((item) => label(item) === "OpenJoystickDriver");
			const menu = appMenu && children(appMenu, "AXMenu")[0];
			const entry = menu && children(menu, "AXMenuItem").find((item) => label(item) === "Settings...");
			if (!entry) throw new Error("the app menu has no Settings... item");
			press(entry);
			const window = waitFor(() => windows(app).find(isSettings), "Settings window did not appear");
			const tab = children(children(window, "AXToolbar")[0], "AXButton").find((button) => label(button) === argument);
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
		case "activate":
			activate(app, pid);
			return "";
		case "raise": {
			activate(app, pid);
			const code = $.AXUIElementPerformAction(find(app, argument), "AXRaise");
			if (code !== 0) throw new Error("raising the " + argument + " window failed with AXError " + code);
			return "";
		}
		case "menu-titles":
			return children(mainMenuBar(app), "AXMenuBarItem")
				.map((item) => {
					const title = label(item);
					if (!title) throw new Error("a main menu bar item has no title");
					return title;
				})
				.join("\n");
		case "open-menu": {
			activate(app, pid);
			const item = children(mainMenuBar(app), "AXMenuBarItem").find((candidate) => label(candidate) === argument);
			if (!item) throw new Error("the main menu bar has no item named " + argument);
			press(item);
			pressPath(item, rest);
			return "";
		}
		case "open-status-menu": {
			activate(app, pid);
			const item = statusMenuBarItem(app);
			press(item);
			pressPath(item, argument === undefined ? [] : [argument, ...rest]);
			return "";
		}
		case "press-escape": {
			for (const down of [true, false]) {
				const event = $.CGEventCreateKeyboardEvent(null, KEY_ESCAPE, down);
				$.CGEventPost($.kCGHIDEventTap, event);
			}
			return "";
		}
		default:
			throw new Error("unknown command " + command);
	}
}
