# Adding Or Changing a Controller Record

This page explains how to add a controller that OpenJoystickDriver does not know, or change how it drives a known one, with your own controller record.

> **Note:** This page applies to OpenJoystickDriver 0.6.0-alpha.1 and later. Version 0.5.0-beta.4 and earlier do not have all of the features on this page.

## Contents

- [How Records Work](#how-records-work)
- [Choose Who Drives the Controller](#choose-who-drives-the-controller)
- [Describe a Controller's Input Reports](#describe-a-controllers-input-reports)
- [Add Rumble To a Controller](#add-rumble-to-a-controller)
- [Send Fixed Reports At Startup](#send-fixed-reports-at-startup)
- [Tune Timings and the Stick Deadzone](#tune-timings-and-the-stick-deadzone)
- [Select a Model With Protocol Parameters](#select-a-model-with-protocol-parameters)
- [Map HID Usages](#map-hid-usages)
- [Offer Alternative Modes Chosen By a Probe](#offer-alternative-modes-chosen-by-a-probe)
- [Connect a Switch 2 Controller Over Bluetooth LE][toc-2]
- [Draft a Record From a Connected Controller][toc-1]
- [Install a Record](#install-a-record)
- [Check Which Records Apply](#check-which-records-apply)
- [Remove a Record](#remove-a-record)
- [Schema Versions and Compatibility](#schema-versions-and-compatibility)
- [Further Reading](#further-reading)

[toc-1]: #draft-a-record-from-a-connected-controller
[toc-2]: #connect-a-switch-2-controller-over-bluetooth-le

## How Records Work

A controller record tells OpenJoystickDriver which protocol family drives one controller model, identified by its VID:PID. The app contains a bundled record for each supported model. Your records are JSON files in `~/Library/Application Support/OpenJoystickDriver/Controllers`. Each file is named after its model in lowercase hexadecimal, for example `045e-028e.json`.

A file in that folder is one of two kinds:

- `Controller`: a complete record for a model that has no bundled record. Name it `VVVV-PPPP.json`.
- `ControllerPatch`: new values for a model that already has a record. Name it `VVVV-PPPP.patch.json`. Its `selector` names the model by `vendorID` and `productID`, and its `patch` holds the fields to change.

A patch follows RFC 7396 JSON Merge Patch. An object in `patch` merges into the record key by key, a value you give replaces the record's value, an array replaces the whole array, and `null` deletes the key. Deleting the last key of a section leaves an empty section, which a record does not accept, so set the whole section (`tuning`, `protocol.parameters`) to `null` instead. A patch that changes `protocol.family` must also set to `null` every `protocol` key of the old family that the new family does not read.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ControllerPatch",
  "selector": { "vendorID": 1118, "productID": 746 },
  "patch": { "tuning": { "stickDeadzone": 0.08 }, "protocol": { "parameters": { "shareButton": null } } }
}
```

Several patches can apply to one model. The layers apply from the weakest to the strongest: the bundled record, a bundled patch, a patch from an installed [mod package](Writing-Controller-Mods.md), then your patch. Inside one layer, a patch with `"selector": { "all": true }` applies first, a `vendorID` and `productID` patch next, and a patch with `"selector": { "model": "VVVV-PPPP" }` last. A `Controller` file of yours replaces a package's `Controller` file for the same model. A `ControllerPatch` of yours applies over the package record instead of replacing it. If you remove the package later, OJD lists your patch as a problem and skips it.

A record for a model that uses raw USB works only when macOS lets OpenJoystickDriver open the device directly. The Xbox USB part of the [OJD driver extension](Connecting-Controllers.md#xbox-usb-driver-extension) claims only the Xbox models in its signed product list, and your record cannot add a model to that list. `ojd record validate` says when this applies.

## Choose Who Drives the Controller

macOS serves some controllers natively through the Game Controller framework. OpenJoystickDriver leaves those to macOS by default and only reads their input. The record's `ownership` field changes this:

- `macos`: macOS drives the controller when it can. This is the default.
- `ojd`: OpenJoystickDriver opens the controller exclusively even when macOS supports it, and drives it like a controller macOS does not know.

A raw-USB family, such as `xbox.gip`, has no `ownership` field, because macOS cannot serve those controllers. A new `ownership` value applies to a connected controller as soon as the running service reloads the records. You do not need to unplug the controller.

To change `ownership` without editing the file, run `ojd controller ownership CONTROLLER native|virtual`. `native` sets `macos`, and `virtual` sets `ojd`. The command writes the value to your record for the model, and creates a `ControllerPatch` file when you have none and the bundled catalog or an installed package has a record of the model. It refuses a raw-USB family, a controller that macOS does not serve natively, and a model that has no record at all, with the code E2023. For a model with no record, run `ojd record draft` to start one. `ojd controller show` names the choice and the layer it comes from. In the app, the controller detail has the same choice as the **Served by** picker, shown for a controller that macOS serves natively or that a record gives to OpenJoystickDriver, and never for a raw-USB family.

## Describe a Controller's Input Reports

Some controllers send fixed input reports that their HID descriptor describes wrongly. A record with the protocol family `hid.report-layout` names where each control sits in the report, in its `input` field. The family requires `input`, and no other family takes it in a record. The bundled `xbox.xid` protocol description declares its own `input` layout as data, in `Resources/Protocols/xbox.xid.json`, with the same fields.

```json
"protocol": { "family": "hid.report-layout" },
"input": {
  "report": { "length": 19 },
  "buttons": [
    { "control": "face-south", "byte": 13, "mask": 128 },
    { "control": "view", "byte": 1, "mask": 1 }
  ],
  "axes": [
    { "control": "left-stick-x", "byte": 3 },
    { "control": "left-stick-y", "byte": 4 }
  ],
  "hat": [
    {
      "encoding": "directions",
      "up": { "byte": 9, "mask": 128 },
      "right": { "byte": 7, "mask": 128 },
      "down": { "byte": 10, "mask": 128 },
      "left": { "byte": 8, "mask": 128 }
    }
  ],
  "leftTrigger": { "byte": 17 },
  "rightTrigger": { "byte": 18 }
}
```

Offsets count from the first byte of the report as macOS delivers it.

- `report`: `length` is the shortest report OpenJoystickDriver reads, from 1 to 64 bytes. With `id`, from 1 to 255, byte 0 must hold that report ID, and `length` counts it. OpenJoystickDriver ignores shorter reports and reports with another ID.
- `buttons`: each entry names a control, a `byte`, and a `mask`. The button is pressed while any masked bit is set. Repeat a control to read it from several places. A button cannot be `dpad`, a stick axis, `left-trigger`, or `right-trigger`.
- `axes`: each entry names a stick axis and its `byte`. `bits` is 8, the default, or 16 for a little-endian value in `byte` and the next byte. `signed` reads the value as two's complement. `min` and `max` set the raw range, which defaults to the full range of the width. `inverted` flips the direction. `symmetric` reads a signed value as the raw value divided by `max`, so the lowest raw value reads as full negative; it requires `signed`; `min` and `max` default to the full range, and if given must be negative and positive. X grows right and Y grows down, as in HID.
- `hat`: a list of sources; the first that reads a direction wins. An `8-way` source reads the masked bits as 0 for north, clockwise to 7 for north-west, and any other value as centered. With `neutralUntilNonzero`, 0 also reads centered until the bits have been nonzero once, for a controller that sends 0 before its hat is live. A `directions` source names one bit for each direction; opposing directions cancel. A `table` source takes a `byte`, a `mask`, and `values`, which maps each masked number, written in decimal without leading zeros, to a direction name from `north`, `northEast`, `east`, `southEast`, `south`, `southWest`, `west`, and `northWest`; any other number reads as centered.
- `leftTrigger` and `rightTrigger`: a `byte` read from 0 to 255, a `button` that reads as fully pulled, or both.

Name at least one control. `ojd record validate` checks that every field lies inside the report.

## Add Rumble To a Controller

A `hid.report-layout` or `vendor.ps3-third-party` controller is input-only unless its record names its rumble report in `output.rumble`:

```json
"output": {
  "rumble": {
    "report": { "kind": "output", "id": 2, "length": 8 },
    "leftMain": { "byte": 3 },
    "rightMain": { "byte": 2 }
  }
}
```

- `report` names the HID report: `kind` is `output` or `feature`, `id` is the report ID, and `length` counts every byte, including the report ID.
- `leftMain`, `rightMain`, `leftTrigger`, and `rightTrigger` each give the byte offset of that motor's intensity, from 0 to 255. Name at least one.

OpenJoystickDriver sets the report ID in byte 0 when the ID is not 0, writes each motor's intensity, and sends 0 in every other byte. It sends this report even when macOS drives the controller, because macOS does not drive these motors.

## Send Fixed Reports At Startup

A HID controller that needs a fixed report before it sends input can name it in `output.startup`. The Sixaxis records use one to enable a DualShock 3 over Bluetooth:

```json
"output": {
  "startup": [
    {
      "report": { "kind": "feature", "id": 244, "length": 5 },
      "bytes": [66, 3, 0, 0],
      "transport": "bluetooth-classic"
    }
  ]
}
```

- `report` names the HID report as in `output.rumble`. `length` is 2 to 64 bytes.
- `bytes` lists every byte after the report ID, or every byte of the report when `id` is 0, from 0 to 255.
- `delayMilliseconds` waits before this write, from 0, the default, to 1000.
- `transport` limits the write to `usb`, `bluetooth-classic`, or `bluetooth-le`. Without it, OpenJoystickDriver sends the write on every transport.

List 1 to 16 writes. OpenJoystickDriver sends them in order after the protocol driver's own startup, only when it opens the controller. A failed write is logged and the next one is still sent. Raw-USB families do not take `output.startup`.

## Tune Timings and the Stick Deadzone

A record's `tuning` field changes a value that the protocol driver otherwise sets. Name at least one value. A value you leave out keeps the driver's default.

```json
"tuning": {
  "stickDeadzone": 0.02,
  "hidStartupRecoveryRounds": 3
}
```

| Field | Range | Applies to | What it sets |
| --- | --- | --- | --- |
| `stickDeadzone` | more than 0, less than 1 | every family | The radial deadzone of both sticks on the virtual gamepad, as a fraction of full deflection. Movement past the deadzone is rescaled to the full range. |
| `inputLivenessTimeoutMs` | 1 to 60000 | `sony.dualshock4` | How long the controller can send no input before OpenJoystickDriver releases its held controls. The default is 1000. |
| `hidStartupIntervalMs` | 0 to 60000 | HID families | The gap between the startup writes. |
| `minimumHIDOutputIntervalMs` | 0 to 60000 | HID families | The shortest gap between rumble and lighting reports. 0 sends them without a limit. |
| `hidStartupRecoveryIntervalMs` | 1 to 60000 | `nintendo.switch1` | The gap between startup recovery rounds. The default is 200. |
| `hidStartupRecoveryRounds` | 1 to 10 | `nintendo.switch1` | The startup recovery rounds before OpenJoystickDriver gives up. The default is 2. |

Raw-USB families, such as `xbox.gip`, do not take the two HID timings. The two recovery values apply only to `nintendo.switch1`, because the `nintendo.switch2` and `nintendo.switch-input-only` drivers have no startup recovery. `ojd record validate` rejects a value outside its range or its families.

A `tuning` in a `ControllerPatch` merges per value into the bundled `tuning`: a value you leave out keeps its bundled value. Timings apply when the running service connects the controller again after the record changes.

### Set a Default for Every Controller

`~/Library/Application Support/OpenJoystickDriver/Controllers/all.patch.json` sets a `tuning` default for every controller. It is a `ControllerPatch` with `"selector": { "all": true }`, and [`controller-patch.schema.json`](../Resources/Schemas/controller-patch.schema.json) describes it. Only `tuning` may appear in its `patch`.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ControllerPatch",
  "selector": { "all": true },
  "patch": { "tuning": { "stickDeadzone": 0.05 } }
}
```

Each value takes the first layer that sets it, from the strongest down: a patch of yours for the model, your `all.patch.json`, the package, the bundled record, then the driver's own default. A value in `all.patch.json` applies only to the families that read it, as in the table above. The file is optional. An invalid file is ignored whole, and `ojd config show`, `ojd status`, and the `config-files` check of `ojd diagnose` report why. `ojd config show` prints each value and the layer that set it.

The record's `stickDeadzone` shapes the virtual gamepad's stick report. A profile's `innerDeadzone` calibrates a stick that the profile maps to aim, flick, pointer, scroll, or steering output. The two do not inherit from each other: a deadzone in a record or in `all.patch.json` does not change what a profile mapping does. `ojd config show --controller` lists the active profile's `innerDeadzone` values in the `profile` layer next to the record's keys, when the service runs.

### Change the Virtual Gamepad Identity

A persona file in `~/Library/Application Support/OpenJoystickDriver/Personas` chooses the virtual gamepad that games see for one controller model, or for one controller unit. [`persona.schema.json`](../Resources/Schemas/persona.schema.json) describes it.

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "Persona",
  "match": { "vendorID": 1356, "productID": 3302 },
  "descriptor": "hid-xbox-one-s-bt"
}
```

`match` names the model by VID:PID in decimal. Add `unit` with a `U-` ID from `ojd controller show` to match one controller. A unit file wins over a model file. `descriptor` is a built-in report descriptor: `hid-xbox-one-s-bt` or `hid-generic`. An optional `identity` gives a vendor ID, product ID, product name, manufacturer, and glyph family (`xbox` or `generic`). OpenJoystickDriver publishes the virtual gamepad with that identity over the built-in descriptor. The transport, the report layout, and the virtual LocationID stay those of the built-in profile, and `versionNumber` defaults to the built-in profile's. While the service runs, it watches the `Personas` folder. When a file is added, edited, or removed and a connected controller's `identity` or `descriptor` changes, OpenJoystickDriver creates that controller's virtual gamepad again with the new identity, so you do not reconnect the controller. Games and other apps see the old virtual gamepad disappear and a new one appear. A change that leaves a controller's identity and descriptor the same, or that concerns another controller, does not touch its virtual gamepad. A file that fails validation is skipped, and `ojd status` and the `config-files` check of `ojd diagnose` name it and the reason. The old `VirtualHIDProfileOverrides` setting is gone and is not migrated, so recreate your overrides as persona files.

## Select a Model With Protocol Parameters

Some families drive several models that differ in one detail. A typed parameter in the record's `protocol.parameters` object selects the detail. Each family declares its own parameters, and a record with an unknown parameter, a parameter another family declares, or a value of the wrong type is rejected. A flag parameter is `true` or left out.

- `shareButton` (`xbox.gip`): `{"fromEnd": N}` reads the Share button N bytes back from the end of the packet (Linux xpad `MAP_SHARE_OFFSET` is 26).
- `layout` (`nintendo.switch1`, `nintendo.switch2`): `Pro`, `JoyConLeft` or `JoyConRight`, and `GameCube` on `nintendo.switch2`, the NSO GameCube controller. `usbProtocol` (`nintendo.switch1`): `ChargingOnly` for a pad whose USB link only charges it, which binds the Bluetooth Classic link only; it excludes `layout`.
- `innerGrips` and `lightingMemory` (`vendor.gamesir`): an enhanced HID record names exactly one. `innerGrips` reports the inner grips; `lightingMemory: "ProfileSlots"` makes lighting memory slot-based. A GameSir USB record names neither.
- `hatSource: "DpadPressure"` (`vendor.ps3-third-party`): any nonzero D-pad pressure byte holds its direction.
- `motionCalibration: "Factory"` (`sony.dualshock4`): read the motion calibration from the controller. Without it, OpenJoystickDriver uses nominal calibration, as for third-party DualShock 4 controllers.
- `role: "WirelessAdapter"` (`sony.dualshock4`): the Sony DUALSHOCK 4 USB wireless adapter. Output waits until a controller connects to the adapter.
- `motionScale: "StrikePad"` (`sony.dualshock4`): a controller whose motion reports half the acceleration in the opposite direction on all axes.
- `reportRevision: "Shield2015"` (`vendor.nvidia-shield`): the 2015 SHIELD controller, which has rumble. Without it, the driver treats the controller as the 2017 model, which is input-only on macOS.
- `maker: "ThirdParty"` (`sony.dualsense`): the controller is not a Sony DualSense. The driver reads feature report `0x03` for its features and limits output to them, as SDL's `HIDAPI_DriverPS5` does.
- `unprobedSensors` and `unprobedTouchpad` (`sony.dualsense`): a third-party DualSense that does not answer the capability probe still has motion sensors or a touchpad, and either parameter reads its input in the alternate report layout.
- `forcedVibration` (`sony.dualsense`): a third-party DualSense keeps vibration when its probe reply omits it.
- `role: "Receiver"` (`sony.dualsense`): a third-party DualSense wireless receiver, which reports with no controller paired. OJD treats the controller as connected only while the packet sequence advances.

A DualShock 4 record takes at most one of `role` and `motionScale`. A `sony.dualsense` record runs as a third-party controller only with `maker: "ThirdParty"`, whatever its vendor ID, and the other DualSense parameters describe that model and need it; a record without parameters is a Sony DualSense. The catalog gives `maker: "ThirdParty"` to every `sony.dualsense` record whose vendor ID is not Sony's (`054C`). A `patch` merges its parameters key by key into the bundled ones and cannot remove one, but it can set a bundled parameter to another value.

## Map HID Usages

A `hid.descriptor` record maps the usages of its report descriptor to controls in `input.hidUsageMap`. Without one, the record uses the standard map in `Resources/Protocols/hid.descriptor.json`. Each entry names a usage by decimal `page` and `usage` and one `control`, as a `kind`:

- `button`: the control is pressed while the value is nonzero. It cannot be `dpad`, a stick axis or a trigger.
- `axis`: the control is a stick axis (`left-stick-x`, `left-stick-y`, `right-stick-x`, `right-stick-y`) or `left-trigger` or `right-trigger`. A stick reads -1 to 1 and a trigger 0 to 1 across the element's logical range. `range` (`{"min": 0, "max": 100}`, `min` below `max`) replaces that range, `inverted` reverses the axis, and `deadZone` (above 0 and below 1) reads 0 within that fraction of full travel and rescales the rest.
- `hat`: the control is `dpad`. `range` is `{"min": 0, "max": 7}` or `{"min": 1, "max": 8}` and names the value of north, then clockwise; any other value is neutral. Without `range`, the element's logical minimum is north.

`reportID` limits the map to one report. A usage the map does not name is ignored, and both the app and `./Scripts/ojd check profiles` reject a usage named twice or an axis `range` whose `min` is not below its `max`. The description may also list `descriptorShapes` that choose a map from the usages a controller's report descriptor declares: the shape in `hid.descriptor.json` gives a controller with Z, Rz, a Brake or Accelerator and no Rx or Ry the Z/Rz layout, with Brake as LT and Accelerator as RT. The records for the WR007 (`11C1:5600`), SCUF Envision (`2E95:434D`), 8BitDo Ultimate 2C (`2DC8:301B`, `301C`) and DragonRise (`0079:0006`, by patch) show complete maps.

## Offer Alternative Modes Chosen By a Probe

Some controllers can run one of several protocols, such as XInput, DInput, or Switch mode. A HID record can list the alternatives in `modes`. The record's own `protocol` is the default mode and has no probes:

```json
"modes": [
  {
    "id": "feature-ef-answers",
    "protocol": { "family": "sony.sixaxis" },
    "match": {
      "probes": [{ "report": 239, "length": 49, "expect": "answers" }]
    }
  }
]
```

- `id` is lowercase words joined by hyphens, and is not `default`. IDs are unique in a record.
- `protocol` names the protocol that mode runs, as the record's own `protocol` does.
- `match.probes` lists 1 or more probes. A mode is selected only when all of its probes hold.
- A probe reads one feature report (`report` 0 to 255, `length` 1 to 65535) and expects `answers`, `stalls`, or `bytes`. `bytes` also takes `offset` and `bytes`, uppercase hex pairs the reply must hold at that offset; the other expectations take neither.

A probe reads a feature report from the controller and selects a mode by the reply. OpenJoystickDriver never switches a controller's mode. It tries the modes in record order and runs the first whose probes all hold. When no mode matches, the default mode runs. A report that several probes name is read once.

A probe only reads. It cannot write to the controller. Each read gives up after 2 seconds. When a probe gets no usable reply, the selection stops, the controller stays enabled in its default mode, and OpenJoystickDriver logs a line that names the report. No usable reply means a timeout, an unavailable route, or any failure other than the controller's own refusal, such as a device that is not open, gone, or held exclusively. Only a stalled pipe (`0xE000404F`) or an unsupported request (`kIOReturnUnsupported`) is a refusal. It satisfies `stalls` and fails the other expectations, so a stall where a mode expects `answers` leaves the default mode running. Probes read HID feature reports, so a controller on another route, such as a Bluetooth LE GATT peripheral, always runs its default mode.

Modes apply to HID controllers only. A record with a raw-USB family cannot use `modes`, and a mode cannot name one. Every mode follows the record-level rules of the default protocol for `input.layout`, `output.rumble`, and `capabilities`. A `patch` can replace `modes`.

The DualShock 3 record carries one mode that probes feature report `0xEF`. It is a candidate discriminator only: the mode runs the same protocol as the default, and the record does not say which unit is genuine. The `length` of 49 is a chosen length, the size of a Sixaxis input report, not a size recorded from a DualShock 3 reply.

## Connect a Switch 2 Controller Over Bluetooth LE

OpenJoystickDriver connects a Nintendo Switch 2 controller over Bluetooth LE only when its record names the GATT characteristic that carries vibration:

```json
"bluetoothLE": {
  "vibrationCharacteristic": "FA19B0FB-CD1F-46A7-84A1-BBB09E00C149"
}
```

Write the UUID in uppercase. Only a `nintendo.switch2` record takes `bluetoothLE`. The service looks for Switch 2 advertisements with the Nintendo vendor ID (`057E`) only.

A Switch 2 record without `bluetoothLE` connects over USB only, and `ojd record validate` and `ojd record show` say so. The bundled Switch 2 records have the section, and a `ControllerPatch` that leaves `bluetoothLE` out keeps the bundled value. A `Controller` for a new Switch 2 model needs its own `bluetoothLE`.

## Draft a Record From a Connected Controller

`ojd record draft CONTROLLER` builds a starting record for a connected controller. The service must be running.

1. Run `ojd record draft CONTROLLER > record.json`, where `CONTROLLER` is an ID from `ojd controller list` or the controller's VID:PID.
2. For 10 seconds, press every button and move each stick, trigger, and the D-pad. `--duration SECONDS` changes the time.
3. Read the bytes that changed. For each report byte that took more than one value, the command prints its offset and its lowest and highest value on stderr.

The record maps what the HID report descriptor states plainly: buttons 1 to 11 in the order the `hid.descriptor` family reads them, X, Y, Rx, and Ry sticks, Z and Rz triggers, and the hat, with the `hid.report-layout` family. When nothing maps, it names `hid.descriptor` instead. Check every control against the changed bytes and correct the record before you install it. The draft is a `ControllerPatch` for a model with a bundled record and a `Controller` otherwise.

## Install a Record

1. Find the VID:PID of your controller. For more information, see [Finding your controller ID](Connecting-Controllers.md#finding-your-controller-id).
2. Write the record file. Set `apiVersion` to `openjoystickdriver/v1alpha1` and `kind` to `Controller` or `ControllerPatch`.
3. Check the file. Run `ojd record validate FILE`.
4. Install the file. Run `ojd record install FILE`.

The running service applies the record when the folder changes. It connects each connected controller of that model again with the new record, and leaves other controllers connected. A controller that you disconnected stays disconnected. You do not need to restart the service or unplug the controller.

## Check Which Records Apply

Run `ojd record list`. Each line shows a model, its protocol family, and its layer: `bundled`, `package`, or `user`.

Run `ojd record show VVVV:PPPP` to see one model's effective record and the layer of each field.

OpenJoystickDriver skips a file that is not valid and uses the bundled record for that model. `ojd record list`, `ojd status`, and `ojd diagnose` name each skipped file and the reason.

## Remove a Record

1. Run `ojd record remove VVVV:PPPP`.
2. Confirm the deletion.

The command removes the `Controller` file and the patch file of that model. A bundled model then goes back to its bundled record.

## Schema Versions and Compatibility

Each file that OJD reads declares `apiVersion: openjoystickdriver/v1alpha1` and its `kind`, such as `Controller`, `ControllerPatch`, `Persona`, `Profile`, or `ModPackage`. Files do not declare `$schema`. OJD accepts only the `apiVersion` it supports and rejects every other one, a missing one, and a `kind` it does not read there. The error names the file, the version it found, and the supported one. It does not convert files. The schemas are flat files in `Resources/Schemas/`, and each `$id` is `https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha1/<kind>.schema.json`. Nothing publishes those IDs yet.

- Before 1.0, a `v1alpha1` schema may change incompatibly. The release notes list each such change and how to update a file.
- At 1.0 the schemas are promoted to `v1`. A `v1` schema takes only additive changes: a new optional field, or a new value where a reader can ignore it.
- A change that is not additive needs a new version, `v2`. OJD names the version it accepts, so a file for an unknown version is rejected rather than half read.

The `--json` output schema has its own release check: within a major version, or a minor version before 1.0, it only gains keys and values. See [Using the command line](Command-Line.md).

## Further Reading

- [Command reference](Command-Reference.md)
- [Writing controller mods](Writing-Controller-Mods.md)
- [Supported controllers](Supported-Controllers.md)
- [Generic HID controllers](Supported-Controllers.md#generic-hid-controllers)
