# Native Repository Tools

Use these probes only for intentional hardware tests.

Build the maintained `SDLGamepadProbe` without opening hardware:

```bash
./Scripts/ojd check tools
```

The build uses Apple Clang, the system `SDL3` package found through `pkg-config`, and the Foundation and GameController frameworks.

To test a connected controller for 10 seconds:

```bash
./Scripts/ojd diagnose sdl3 --seconds 10
```

`--seconds` takes a whole number from 1 to 3600 and defaults to 10; other values exit with code 2.

Expected result: the probe lists SDL gamepad events and exits after 10 seconds. Axis events print once per excursion for each gamepad and axis: `GAMEPAD_AXIS which=3 axis=4 left-rest value=8006` when the axis passes 8000, then `GAMEPAD_AXIS which=3 axis=4 rest value=0 peak=32767` when it falls below 2000, with the signed value of largest magnitude as `peak`. Add `--rumble` only when you intend to activate output on every SDL gamepad.

## WebRTC Bridge

`Tools/WebRTCBridge/` is a separate Swift package with its own `Package.swift`. It depends on LiveKitWebRTC, and the root package, `swift test` at the repository root and `./Scripts/ojd check tools` do not fetch or build it. Build and test it on its own:

```bash
cd Tools/WebRTCBridge
swift test
```

The first build downloads the LiveKitWebRTC XCFramework, about 70 MB. See [WebRTC Bridge](../docs/sdk/webrtc-bridge.md) for the roles and the steps.
