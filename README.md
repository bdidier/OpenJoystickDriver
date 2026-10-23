# OpenJoystickDriver

Use the controller you already own with Mac games.

OpenJoystickDriver (OJD) is a free, open-source menu-bar app.
It reads a controller over USB, Bluetooth, or a 2.4 GHz dongle and shows it to games as a standard virtual controller, including controllers that macOS does not support.

[![Latest release][release-badge]][releases] [![macOS 12 or later][macos-badge]](#requirements) [![License][license-badge]](LICENSE) [![GitHub Sponsors][sponsor-badge]][sponsor]

![The Controllers area with a DualShock 3 that OJD serves as a virtual gamepad](docs/screenshots/main-controllers.png)

> [!WARNING]
> OJD is alpha software.
> Many controllers have no hardware test yet, and some games do not read the virtual controller.
> Check [Supported controllers][wiki-supported] and [Playing games][wiki-games] before you rely on it.

## Features

- **696 controller records:** Xbox, PlayStation, Nintendo Switch, Steam, GameSir, NVIDIA SHIELD, Flydigi, and generic HID gamepads.
  The [support table][wiki-supported] shows which ones have a hardware test.
- **Two virtual controller profiles:** an Xbox Wireless Controller (`SDLCompatible`) or a generic gamepad (`Generic`), one for each physical controller.
- **SDL mappings:** `ojd virtual launch` starts a game with the mapping of your virtual controllers.
- **Remapping:** buttons, combinations, sequences, and layers, plus keyboard, pointer, and scroll output.
- **Input test:** see each button, stick, and trigger before you play.
- **Mods:** install shared controllers, patches, profiles, and virtual devices with `ojd mod install`.
- **No kernel extension:** SIP and AMFI stay on.

## Requirements

- macOS 12 (Monterey) or later, on Apple silicon or Intel.

## Install

1. Download the `.dmg` from the [latest release][releases].
2. Drag **OpenJoystickDriver.app** into **Applications**, and open it from there.
3. If macOS asks, allow the login item in **System Settings** > **General** > **Login Items**.
4. For an Xbox One or Xbox Series controller on USB, also allow the driver extension in **System Settings** > **General** > **Login Items & Extensions** > **Driver Extensions**.

To build the app yourself, see [Building from source][wiki-build].

## Quick Start

1. Click the controller icon in the menu bar.
   If it shows **Grant Access**, click it and allow OJD in **Input Monitoring** and **Accessibility**.
2. Connect your controller.
3. Select it in **Controllers** and click **Open Input Test...** to check each control.
4. Start a game.

If something does not work, see [Troubleshooting][wiki-troubleshooting].

<details>
<summary>More screenshots</summary>

![The menu-bar item menu](docs/screenshots/menu-bar-item.png)
![The Library area with an installed controller record](docs/screenshots/main-library.png)
![The Activity area showing the live log](docs/screenshots/main-activity.png)
![The General pane of the Settings window](docs/screenshots/settings-general.png)

</details>

## Documentation

- [Wiki][wiki]: [Getting started][wiki-start], [Using the app][wiki-app], [Remapping profiles][wiki-remap], [Command reference][wiki-cli].
- [Reporting a bug][wiki-bug]: send a bug or a controller test result.
- [CONTRIBUTING.md](CONTRIBUTING.md), [LOCALIZATION.md](LOCALIZATION.md), and [SECURITY.md](SECURITY.md).

## Support

Star the repository to help other Mac players find it.
[GitHub Sponsors][sponsor] pays for the tools that build the app and for the controllers tested on the maintainer's Macs: Apple silicon on macOS 27 and Intel on macOS 12.

[![Star History Chart][star-chart]][star-history]

## License

[MIT](LICENSE).
Xbox and PlayStation are trademarks of [Microsoft](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) and [Sony](https://www.playstation.com/en-us/legal/copyright-and-trademark-notice/).
This project is not affiliated with either.

[release-badge]: https://img.shields.io/github/v/release/xsyetopz/OpenJoystickDriver?include_prereleases
[macos-badge]: https://img.shields.io/badge/macOS-12%2B-000000?logo=apple
[license-badge]: https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver
[sponsor-badge]: https://img.shields.io/badge/sponsor-30363D?logo=githubsponsors&logoColor=EA4AAA
[releases]: https://github.com/xsyetopz/OpenJoystickDriver/releases
[sponsor]: https://github.com/sponsors/xsyetopz
[wiki]: https://github.com/xsyetopz/OpenJoystickDriver/wiki
[wiki-supported]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers
[wiki-games]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Playing-Games
[wiki-build]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Building-from-Source
[wiki-troubleshooting]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Troubleshooting
[wiki-start]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Getting-Started
[wiki-app]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Using-the-App
[wiki-remap]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Remapping-Profiles
[wiki-cli]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Command-Reference
[wiki-bug]: https://github.com/xsyetopz/OpenJoystickDriver/wiki/Reporting-a-Bug
[star-chart]: https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left&sealed_token=PjXIM3WljCuileJs_cIh3xVcAUk_S-XIvzSI-4YZXyrdXUDv_5yKL-bki0BDGSsz92-vhQ9_yqKPxyBC0RsY1Cd0C-e0YWUXePQkgLZcoXOiDCgazJpBqvW2rzdCZb8gK-1y7jncPZsFa8yqvijYWxA1UuP7Kw2Knvq2XnUuoMlTbtNobOEAx47QZF0U
[star-history]: https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left
