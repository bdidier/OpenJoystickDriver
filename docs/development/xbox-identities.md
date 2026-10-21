# Xbox Fallback Identities

A safe published virtual profile needs more than a product name:

1. an exact virtual VID/PID;
2. the matching descriptor and report bytes;
3. a live `GCController.supportsHIDDevice` result where GameController.framework matters;
4. hardware evidence for GameController.framework claims.

OJD publishes exactly two virtual HID profiles, `SDLCompatible` and `Generic`; `VirtualHIDProfileSelector` picks `SDLCompatible` when a controller's declared controls fit it, otherwise `Generic`. See [CLI and Application Runtime](cli-and-runtime.md) for the selection and override contract.

Linux `xpad.c` identifies physical devices for Linux. It does not prove that a macOS virtual HID device can impersonate them.

## Evidence: SDLCompatible

`SDLCompatible` is the only Xbox One Bluetooth-shaped profile. It publishes `045e:02fd` with an approximated descriptor until a genuine capture exists. Recorded `045e:02fd` experiments with the BT1 and BT2 descriptors produced no usable SDL HIDAPI input. GameSir G7 SE USB GIP is hardware-verified for GameController.framework. Physical GIP sends Hello plus one rest `0x20`, then change-only input; a status-only packet log after that is not a failed init. A custom SDL 3.4.16 HIDAPI xboxone build bound the Bluetooth `045e:0b13` identity and used the 17-byte BLE path; a 12s interrupt watch stayed idle (no physical button). Steam `hid_init` hangs. Recorded DualShock 4 and DualSense identities published from that GIP pad returned `GCController.supportsHIDDevice` and custom HIDAPI `SDL_OpenGamepad`; OJD publishes no DualShock 4 or DualSense profile.

OJD has several physical records and parsers for other Xbox controller families but no distinct virtual profile beyond `SDLCompatible` and `Generic`.

## Apple Audit

The GameController MobileAsset version `10.5.2` downloaded on 2026-07-12 had no exact entry for `045e:028e`, `045e:02ea`, or `9886:0024`. This applies only to that system and asset version. Check again after macOS or MobileAsset updates:

```bash
ojd diagnose --output /tmp/ojd-support.json
jq .systemGamepadAudit /tmp/ojd-support.json
```

The support report from the app uses the same audit.

## Selection and Overrides

`VirtualHIDProfileSelector` does not persist its own choice; it runs automatically unless the controller's model (vendor/product) has a stored override. Automatic selection carries no regard for protocol family or foreground consumer; both profiles carry every primary control, so automatic selection always picks `SDLCompatible` when it fits, else `Generic`.

## Promotion Checks

Promoting `SDLCompatible`'s approximated `045e:02fd` descriptor to a genuine capture needs a verified consumer result from SDL and GameController probes covering input, reconnect, rumble, and lights before the descriptor changes.
