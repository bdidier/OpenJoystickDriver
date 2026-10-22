# OpenJoystickDriver

Use game controllers on macOS that macOS does not support natively.

[![GitHub Repo stars][1]](https://github.com/xsyetopz/OpenJoystickDriver/stargazers) [![License][2]](LICENSE) [![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)

> [!
> WARNING]
> Version 0.6.0-alpha.1 is alpha software.
> Some controllers are not tested on real hardware, and some games and apps do not read the virtual controller.
> See [Supported controllers](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers) and [Playing games](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Playing-Games) for what is confirmed.

OpenJoystickDriver (OJD) is a macOS menu-bar app.
It reads a physical controller over USB, Bluetooth, or a 2.4 GHz dongle and shows macOS games a standard virtual controller.

## What It Does

- **Many controller families.
  ** A built-in catalog of 696 controller records covers Xbox, PlayStation, Nintendo Switch, Steam, GameSir, NVIDIA SHIELD, Flydigi, and generic HID gamepads.
  A record does not prove that a controller works: only the controllers that the [support table](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers) lists as Official or Community-verified have a hardware test.
- **A virtual gamepad for games.
  ** Games read one virtual controller for each physical controller, as an Xbox Wireless Controller profile (`SDLCompatible`) or a generic gamepad profile (`Generic`).
  OJD selects the profile.
- **SDL and Steam.** `ojd virtual launch` starts a program with the SDL mapping of your virtual controllers, and `ojd virtual export-mapping` prints SDL and W3C mappings.
  Steam is not verified to work.
- **Profiles and remapping.
  ** Assign buttons, combinations, sequences, and layers, and send controller input as keyboard, pointer, or scroll events.
- **Mods.
  ** Share controllers, patches, profiles, and virtual devices as a folder and install it with `ojd mod`.
- **No kernel extension.
  ** OJD does not need you to turn off SIP or AMFI.

## Screenshots

<!-- screenshot: controllers -->

<!-- screenshot: input-test -->

<!-- screenshot: profiles -->

<!-- screenshot: library -->

<!-- screenshot: menu-bar -->

## Install

1. Download `OpenJoystickDriver-VERSION-macOS.dmg` from the [releases](https://github.com/xsyetopz/OpenJoystickDriver/releases).
2. Open the disk image and drag **OpenJoystickDriver.app** onto the **Applications** shortcut.
3. Open **OpenJoystickDriver** from the Applications folder.
   Keep it in `/Applications`.
4. If macOS asks, allow the login item in **System Settings** > **General** > **Login Items**.

To build the app yourself, see [Building from source](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Building-from-Source).

## System Requirements

- macOS 12 (Monterey) or later.
- A Mac with Apple silicon or an Intel processor.
  The app contains both.
- A controller.

## Quick Start

1. Click the controller icon in the menu bar.
   If the menu shows **Grant Access**, click it and allow OJD in **Input Monitoring** and **Accessibility**.
2. Connect your controller.
3. In the **Controllers** area, select the controller and click **Open Input Test...** to see each control.
4. Play a game.
   The game reads the virtual controller.

If something does not work, see [Troubleshooting](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Troubleshooting).

## Star This Project

If OJD makes your controller work, star the repository.
It helps other Mac players find it.

[Star OpenJoystickDriver on GitHub](https://github.com/xsyetopz/OpenJoystickDriver)

## Sponsorship

![Github-sponsors][3]

[Sponsor the project](https://github.com/sponsors/xsyetopz). The money pays for the tools used to build the apps and for the controllers tested directly on the maintainer's Macs: Apple silicon on macOS 27 and Intel on macOS 12.

## Documentation and Contributing

- User documentation: the [wiki](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Home), starting with [Getting started](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Getting-Started), [Using the app](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Using-the-App), and [Remapping profiles](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Remapping-Profiles).
- Tested a controller: [Reporting a bug](https://github.com/xsyetopz/OpenJoystickDriver/wiki/Reporting-a-Bug) explains how to send the result.
- Contribute: [CONTRIBUTING.md](CONTRIBUTING.md), [docs/README.md](docs/README.md), [LOCALIZATION.md](LOCALIZATION.md), [Tools/README.md](Tools/README.md), and [AGENTS.md](AGENTS.md).
- Security: [SECURITY.md](SECURITY.md).

Xbox and PlayStation names in the UI are trademarks of Microsoft and Sony.
This project is not affiliated with either. [Microsoft](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) · [PlayStation](https://www.playstation.com/en-us/legal/copyright-and-trademark-notice/).

## License

[MIT](LICENSE)

## Star History

[![Star History Chart][4]][5]

[1]: https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social
[2]: https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver
[3]: https://img.shields.io/badge/sponsor-30363D?style=for-the-badge&logo=GitHub-Sponsors&logoColor=#EA4AAA
[4]: https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U
[5]: https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left
