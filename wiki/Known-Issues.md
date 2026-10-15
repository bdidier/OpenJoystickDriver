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

## An Old Virtual HID Extension Is Still Active

An earlier beta installed a different extension, `com.openjoystickdriver.VirtualHIDDevice`. It no longer exists. OJD now has one extension, `com.openjoystickdriver.XboxUSBDevice`, and the app publishes the virtual controller itself. OJD does not remove the old extension, so it can stay listed after you update.

To turn it off, open **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions** and turn off `com.openjoystickdriver.VirtualHIDDevice`.

Do not turn off SIP or AMFI.

## The USB Extension Serves Only Seven Xbox Controllers

The `com.openjoystickdriver.XboxUSBDevice` extension can only match the seven Microsoft USB IDs in Apple's grant: `045E:02D1`, `045E:02DD`, `045E:02E3`, `045E:02EA`, `045E:0B00`, `045E:0B0A`, and `045E:0B12`. OJD reaches every other wired Xbox controller through raw USB access or leaves it to macOS. Adding an ID to the extension needs a new request to Apple, so the list stays as it is until Apple grants more.

## Some Apps Do Not Read the Virtual Controller

Steam, CrossOver, RPCS3, and older games that use SDL2 or IOHIDManager may not read the virtual Xbox controller. For more information, see [Game and app compatibility](Playing-Games.md).

## Further Reading

- [Game does not see the controller](Troubleshooting.md#game-does-not-see-the-controller)
- [Reporting a bug](Reporting-a-Bug.md)
