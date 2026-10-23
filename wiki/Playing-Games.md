# Playing Games

This page explains how games and apps see your controller through OpenJoystickDriver (OJD), which games and apps work, and what to expect from rumble.

## Contents

- [How Games See Your Controller](#how-games-see-your-controller)
- [Game and App Compatibility](#game-and-app-compatibility)
- [Rumble and Lighting](#rumble-and-lighting)
- [Further Reading](#further-reading)

## How Games See Your Controller

Games do not read your physical controller. OJD reads it and publishes one virtual controller for each physical controller. Games read the virtual controller. The virtual controller uses one of three profiles.

### Virtual Controller Profiles

| Profile | Shown to games as | VID:PID | Rumble |
| --- | --- | --- | --- |
| `SDLCompatible` | Xbox Adaptive Controller, Microsoft, USB | `045E:0B0C` | Accepts rumble output |
| `GameControllerCompatible` | Xbox Wireless Controller, Microsoft, Bluetooth | `045E:0B13` | Accepts rumble output |
| `Generic` | OpenJoystickDriver Generic HID Gamepad, USB | `1209:4A4F` | Input only |

The `SDLCompatible` profile is an approximation of an Xbox controller. It is not a byte-exact copy of a real controller. SDL games, Steam, and emulators read it as an Xbox pad named Xbox Adaptive Controller. Apple's GameController framework, which Safari and some Mac games use, does not see it. The `GameControllerCompatible` profile sends the reports of an Xbox Series controller over Bluetooth, which Apple's GameController framework reads. OJD never picks it by itself; choose it with `ojd virtual set game-controller-compatible CONTROLLER`. SDL reads its reports as USB Xbox One packets, so SDL games read no input from it. Steam lists it as "Xbox Series X Controller" with no input and no rumble; use `SDLCompatible` for Steam. Start another SDL game with `ojd virtual launch --sdl-gamecontroller-backend PROGRAM`, which makes SDL read it through the GameController framework. With a Razer Wolverine Tournament Edition, a GameController game read every control except Guide and Share. With input from `ojd virtual feed`, Guide reaches the game in front, and Share reaches no game. The `Generic` profile has 16 buttons and no hat. The D-pad uses four of the 16 buttons.

### Automatic Selection

OJD picks a profile for each controller model in this order:

1. The override that you set for the model, if the profile fits the controller.
2. The `SDLCompatible` profile, if it fits the main controls of the controller.
3. The `Generic` profile.

Automatic selection never picks `GameControllerCompatible`.

The choice does not depend on the game, the macOS version, or the vendor. Both profiles carry every main control, so OJD chooses the Xbox profile for every controller unless you set an override. PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) map every control of the Xbox profile as an Xbox pad: A, B, X, Y, LB, RB, View, Menu, both sticks, both triggers, the D-pad, Xbox, and both rumble motors. With the `Generic` profile, they report "No generic bindings were generated for device 'SDL-0'". The maintainer tested this on macOS 27 with the Xbox profile on `045E:02FD`. SDL reads `045E:0B0C` with the same code; these apps are not yet tested on it.

OJD does not publish a virtual controller if macOS already handles the controller natively. The controller detail shows this state as **Left to macOS**.

### Change the Profile For a Model

OJD is designed to choose the profile for you. You do not need a different setting for each game. Change the profile only to test a problem, and report the result so that the automatic choice can improve. For more information, see [Reporting a bug](Reporting-a-Bug.md).

1. Open the **Controllers** area.
2. Select your controller.
3. Expand **Advanced**.
4. In **Virtual HID profile**, select a profile.

Select **Automatic** to remove the override. The override applies to every connected controller of the same model. For more information, see [Controllers area](Using-the-App.md#controllers-area).

## Game and App Compatibility

This section lists which games and apps read the OJD virtual controller, based on tester results.

> [!NOTE]
> These results come from one tester (gornobatov) on macOS 26.7.1 with a ZD Ultimate Legend dongle and the `045E:02FD` Xbox profile. The maintainer has not verified them on hardware. They are not a guarantee.

Games read controllers through different programming interfaces. The interface decides whether a game sees the OJD virtual controller. OJD cannot add support to another app. For example, each app that uses SDL includes its own SDL version.

### Results By Interface

| Interface | App | Xbox profile result |
| --- | --- | --- |
| OJD | Input Test | Works |
| macOS | Game Controllers in **System Settings** | Lists `GameControllerCompatible`. Does not list `SDLCompatible`, which Apple's GameController framework does not see |
| Browser | Gamepad API | Does not fully work. With a Razer Wolverine Tournament Edition and a GameSir pad, the maintainer saw: Chrome reads `Generic` with the triggers on axes 4 and 5 and no rumble, as that profile is made, but the Razer right stick rests at -0.25 on axis 2. Safari does not list `Generic`, and does not see `SDLCompatible` through Apple's GameController framework. Firefox 158.0.1 maps many controls of `SDLCompatible` wrongly with no rumble, and maps `Generic` wrongly with the right stick at rest at -0.17 on axis 2. With `GameControllerCompatible`, Safari reads every button of the Razer and moves its rumble motors. |
| Apple Game Controller framework | Silksong (GOG) | Use `GameControllerCompatible`, because the framework does not see `SDLCompatible`, and turn on the game's native gamepad or MFi options |
| Native macOS games | Non-Steam native games | Works |
| SDL | Steam | Works in a test on `045E:02FD`: Steam lists the `SDLCompatible` profile as "Xbox One S Controller", needs no setup, reads every control, and moves the rumble motors. SDL reads `045E:0B0C` with the same code and names it "Xbox Adaptive Controller"; Steam is not yet tested on it. macOS reports the virtual controller's transport as `Virtual`, so SDL reads its reports as USB Xbox One packets, and the profile sends those packets for input and takes them for rumble. |
| Wine | CrossOver | Does not work. Sees no controller |
| SDL | RPCS3 | Not verified on hardware. SDL names the profile "Xbox Adaptive Controller" and reads it like Steam does |
| IOHIDManager or SDL2 | Super Meat Boy, Cuphead, LEGO Marvel's Avengers, older Unity or Feral ports | Does not work. These games do not detect the controller |

### Generic HID Profile Results

| App | Generic HID profile result |
| --- | --- |
| OpenEmu | Works. The Xbox profile maps buttons wrongly. |
| Steam | Listed as "OpenJoystickDriver Generic HID Gamepad" and needs **Begin Setup**. Skip the Guide step, because the guide button opens Big Picture mode. One tester saw it erratic and slow to respond. |

OJD is designed to make one automatic choice work across these interfaces. The failures above are known issues, not settings that you must change. For more information, see [How games see your controller](#how-games-see-your-controller).

### Start an App With the SDL Mapping

`ojd virtual launch PROGRAM` runs a program and sets `SDL_GAMECONTROLLERCONFIG` for it to the SDL mapping of each virtual controller that OJD publishes, so SDL in that program lists them. PCSX2 2.8.2 (SDL 3.4.12) and DuckStation (SDL 3.4.16) map the `SDLCompatible` profile as an Xbox pad without this command, but a `Generic` controller gets no gamepad mapping in them without it. `ojd virtual launch --sdl-gamecontroller-backend PROGRAM` also sets the SDL hints that make SDL read controllers only through Apple's GameController framework. OJD sets the variable only for programs that it starts. The maintainer has not verified on hardware that a game lists a controller this way. For more information, see [Command reference](Command-Reference.md).

### Workaround For One Controller

The tester switched the ZD Ultimate Legend itself to Switch Pro mode (`057E:2009`). In that mode macOS handles the controller natively. The controller detail shows **Left to macOS**, and OJD does not publish a virtual controller. RPCS3, the browser, and System Settings then work. HD Rumble in that mode drives only the linear haptics.

Not verified: this workaround for other controllers.

## Rumble and Lighting

This section explains what reaches your physical controller when a game sends rumble.

### Rumble From Games

The `SDLCompatible` virtual controller accepts rumble output. When a game sends rumble, OJD turns it into one short rumble command for the physical controller. OJD sends a stop command when the rumble ends. The maintainer has not verified rumble in games on hardware.

Only rumble reaches the physical controller. OJD does not pass lightbar or lighting commands from games to the controller. The `Generic` profile has no rumble.

The controller must support rumble. If it does not support a motor, OJD drops that channel. Controllers that use Generic HID have no rumble.

### Rumble From Input Test

Input Test has its own **Rumble** and **Lighting** groups. They talk to the controller directly and do not use a game. For more information, see [Testing a controller](Testing-a-Controller.md).

### Identical Controllers

Known issue: if two controllers have the same VID:PID, rumble from games and from System Settings does not reach either controller. Rumble in Input Test still works.

## Further Reading

- [Game does not see the controller](Troubleshooting.md)
- [Known issues](Known-Issues.md)
