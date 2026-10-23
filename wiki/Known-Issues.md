# Known Issues

This page lists current OpenJoystickDriver (OJD) bugs and limits, with a workaround for each.

## Two Global Profiles For One Controller Model Crash the App

If two profiles with global scope are active for the same controller model, OJD crashes at every start.

To recover:

1. Quit OJD.
2. Move `~/Library/Application Support/OpenJoystickDriver/ActiveProfiles.json` to another folder.
3. Open OJD.

OJD then opens with your profiles and none of them active. Do not activate a second global profile for a model that already has one. For more information, see [App crashes or does not start](Troubleshooting.md#app-crashes-or-does-not-start).

## Rumble Does Not Reach Two Identical Controllers

When two controllers have the same VID:PID, rumble from games and from **System Settings** does not reach either controller. Rumble from the **Input Test** window works.

## Unplugging a USB Controller Can Crash the App

If you unplug a USB controller or dongle while OJD runs, OJD may crash. It may also leave stale virtual controllers in **System Settings**. Restart OJD to clear them.

## The Virtual Controller Override Applies To Every Controller Of a Model

The virtual controller override in the controller detail applies to every connected controller with the same VID:PID. This is by design.

## The USB Extension Serves Only Seven Xbox Controllers

The `com.openjoystickdriver.XboxUSBDevice` extension can only match the seven Microsoft USB IDs in Apple's grant: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`. OJD reaches every other wired Xbox controller through raw USB access or leaves it to macOS. Adding an ID to the extension needs a new request to Apple, so the list stays as it is until Apple grants more.

## Another App Reads a USB Controller Directly

Steam or another app can open the USB interface of a controller exclusively. OJD never requests or seizes that interface. The controller detail and `ojd controller list` show **Used by** with the app name and process ID, as the USB host reports them. The state is informational, not an error. OJD opens the controller when the app releases it. Whether the host announces every release has not been confirmed on hardware.

## Some Apps Do Not Read the Virtual Controller

CrossOver and older games that use SDL2 or IOHIDManager may not read the virtual Xbox controller. Steam and RPCS3 list the `SDLCompatible` profile as "Xbox One S Controller". macOS reports its transport as `Virtual`, so SDL reads its reports as USB Xbox One packets, and the profile sends and takes those packets. The maintainer has not verified input or rumble in Steam on hardware. For more information, see [Game and app compatibility](Playing-Games.md).

## macOS Still Lists Its Own Pad For a DualShock 3

While OJD serves a DualShock 3 over USB, it holds the pad exclusively, so other apps cannot open it and macOS delivers the pad's input only to OJD. macOS still binds `AppleGCHIDUserEventDriver` to the pad and GameController still lists a second, synthetic "PLAYSTATION(R)3 Controller" (`05AC:0004`). Steam lists that pad as a "PLAYSTATION(R)3 Controller" over Bluetooth beside OJD's virtual controller. Choose OJD's virtual controller in the game and ignore the other one. When another app already holds the pad exclusively, the controller's detail and `ojd controller list` show "Owned by another app" and OJD reads no input until that app lets go. `ojd diagnose` reports `hid-input-drops`: a warning means the system dropped input reports before OJD read them.

## The OJD Menu Closes While Steam Is Open

Steam brings its window to the front again while connected controllers send input, and macOS closes an open menu of another app when that happens.
Click the OJD icon in the menu bar again, or switch to another app first.

## Further Reading

- [Game does not see the controller](Troubleshooting.md#game-does-not-see-the-controller)
- [Reporting a bug](Reporting-a-Bug.md)
