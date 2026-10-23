# Xbox Fallback Identities

A safe published virtual profile needs more than a product name:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result where GameController.framework matters;
4. hardware evidence for GameController.framework claims.

OJD publishes three virtual HID profiles, `SDLCompatible`, `GameControllerCompatible` and `Generic`; `VirtualHIDProfileSelector` picks `SDLCompatible` when a controller's declared controls fit it, otherwise `Generic`, and publishes `GameControllerCompatible` only on an override. See [CLI and Application Runtime](cli-and-runtime.md) for the selection and override contract.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

## Evidence: SDLCompatible

`SDLCompatible` is the only Xbox One GIP-framed virtual profile. It publishes `045e:02fd` with transport `USB` and a descriptor of OJD's own that carries SDL's USB GIP packets as HID reports, until a genuine capture exists. macOS 27 reports the transport of every `IOHIDUserDevice` as `Virtual`, and SDL 3.4.16 reads only a transport that starts with `Bluetooth` as the Bluetooth bus (`src/hidapi/mac/hid.c:551-568`, `:671-697`), so its Xbox One driver parses the device as USB GIP (`src/joystick/hidapi/SDL_hidapi_xboxone.c:1935-2002`): the report ID is the GIP command, input is command `0x20` (`:1036-1233`) and Guide is command `0x07` (`:1242-1247`). It writes rumble as command `0x09` (`:533-591`). `XboxOneGIPHIDDescriptor` and `XboxOneGIPHIDReportFormat` implement those bytes, and `XboxOneGIPSDLOracleTests` parses them as SDL does. Recorded `045e:02fd` experiments with a Bluetooth-layout descriptor (input report 1, rumble report 3) produced no SDL HIDAPI input and no rumble. GameSir G7 SE USB GIP is hardware-verified for GameController.framework. Physical GIP sends Hello plus one rest `0x20`, then change-only input; a status-only packet log after that is not a failed init. A custom SDL 3.4.16 HIDAPI xboxone build bound the Bluetooth `045e:0b13` identity and used the 17-byte BLE path; a 12s interrupt watch stayed idle (no physical button). Steam `hid_init` hangs. Recorded DualShock 4 and DualSense identities published from that GIP pad returned `GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`; OJD publishes no DualShock 4 or DualSense profile.

## Evidence: GameControllerCompatible

Apple's GameController framework binds `SDLCompatible`'s `045e:02fd` as "Xbox Wireless Controller (Xbox One)" and reads no input from its GIP-framed reports (`OpenJoystickDriverGameControllerProbe` reports `live_input=false`). Apple's personality kext lists `045e:0b13` with `GCIOMatchVirtual`, so the framework matches a virtual device with that ID, and GameSir G7 SE USB GIP published as `045e:0b13` is hardware-verified for GameController.framework. `GameControllerCompatible` publishes `045e:0b13` with transport `Bluetooth` and layout `XboxSeriesBluetooth` (`XboxSeriesBluetoothReport`): input report 1 is 17 bytes with four 16-bit sticks, two 10-bit triggers, a hat, 15 buttons and Share as Consumer `0xB2`, and output report 3 carries rumble. It states `worksWithDefaultSDLHints: false`, because SDL on macOS reads it through HIDAPI only when the transport reports Bluetooth, and macOS 27 reports `Virtual`; `ojd virtual launch --sdl-gamecontroller-backend` makes SDL read it through GameController.

OJD has several physical records and parsers for other Xbox controller families but no distinct virtual profile beyond these three.

## Apple Audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. This applies only to that system and asset version. Check again after macOS or MobileAsset updates:

```bash
ojd diagnose --output /tmp/ojd-support.json
jq .systemGamepadAudit /tmp/ojd-support.json
```

The support report from the app uses the same audit.

## Selection and Overrides

`VirtualHIDProfileSelector` does not persist its own choice; it runs automatically unless the controller's model (vendor/product) has a stored override. Automatic selection carries no regard for protocol family or foreground consumer; both profiles carry every primary control, so automatic selection always picks `SDLCompatible` when it fits, else `Generic`. It never picks `GameControllerCompatible`.

## Promotion Checks

Promoting `SDLCompatible`'s approximated `045e:02fd` descriptor to a genuine capture needs a verified consumer result from SDL and GameController probes covering input, reconnect, rumble, and lights before the descriptor changes.
