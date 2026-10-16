# Writing controller mods

The product list of the [Xbox USB driver extension](Connecting-Controllers.md#xbox-usb-driver-extension) is signed by Apple, and a mod package cannot add a controller to it.

## Contents

- [Package Layout](#package-layout)
- [The Manifest](#the-manifest)
- [Precedence and Clashes](#precedence-and-clashes)
- [Package Profiles Are Read-Only](#package-profiles-are-read-only)
- [Manage Packages With ojd mod](#manage-packages-with-ojd-mod)
- [Further Reading](#further-reading)

## Package Layout

A mod package is a folder that holds controller records, remapping profiles, and virtual gamepad personas. You can share the folder and install it with `ojd mod`.

A package adds files to the layers that OpenJoystickDriver (OJD) already reads. It holds no code. A package record for a raw-USB controller works only when macOS lets OJD open the device directly.

A package is a folder with a `mod.json` manifest and up to three subfolders:

```text
ojd-sample/
  mod.json
  Controllers/1209-0001.json
  Profiles/sample-pad.json
  Personas/1209-0001.json
```

- `Controllers/` holds [controller records](Controller-Records.md). Name a `Controller` file `vvvv-pppp.json` after its model, in lowercase hexadecimal. Name a `ControllerPatch` file `vvvv-pppp.patch.json`, `model-vvvv-pppp.patch.json`, or `all.patch.json`.
- `Profiles/` holds [remapping profiles](Profile-File-Reference.md).
- `Personas/` holds virtual gamepad personas. Name each file `vvvv-pppp.json` after the model it matches, or `vvvv-pppp-U-UNIT.json` for one controller, where `UNIT` is the 16-character unit ID that `ojd controller show` prints.

The sample package, `ojd-sample`, is in the [`docs/sdk/sample`](../docs/sdk/sample) folder of the repository. It adds a generic HID pad (`1209:0001`), a profile that maps Start to the space key, and a persona.

A package folder holds nothing else. OJD refuses a package with a file or folder that is not in the layout, and a package with a link. It skips hidden files.

## The Manifest

The `mod.json` file names the package and lists every file it holds. This is the sample manifest:

```json
{
  "apiVersion": "openjoystickdriver/v1alpha1",
  "kind": "ModPackage",
  "name": "ojd-sample",
  "version": "1.0.0",
  "author": "OpenJoystickDriver",
  "requires": { "minimum": "0.6.0-alpha.1", "below": "0.7.0" },
  "records": ["1209-0001.json"],
  "profiles": ["sample-pad.json"],
  "personas": ["1209-0001.json"]
}
```

- `apiVersion`: `openjoystickdriver/v1alpha1`. OJD rejects a missing or any other version, and names the file, the version it found, and the supported one.
- `kind`: `ModPackage`.
- `name`: Lowercase letters, digits, and hyphens. The package installs into a folder of this name.
- `version`: A SemVer version without a `v` prefix.
- `author`: Text that is not empty.
- `requires`: The OJD versions the package runs on. `minimum` is the first version, and `below` is the first version that is too new. `below` is optional. Prerelease versions follow SemVer order.
- `records`, `profiles`, `personas`: The file names in each subfolder. A list that you include must name at least one file. At least one of the three lists must name a file.

A file that is in a subfolder but not in the manifest, or in the manifest but not in the folder, makes OJD refuse the package. Each listed file must be valid for its kind.

OJD does not use a package whose `requires` leaves out the running version. It skips the package and lists the reason. `ojd mod list` shows it with the code E4002. A development build, whose version is not a SemVer version, uses every package, but `ojd mod validate` and `ojd mod install` refuse every package on it.

## Precedence and Clashes

A package is a read-only layer between the bundled catalog and your own files. When you and a package both have a `Controller` file for a model, OJD uses your file and ignores the package file. Your `ControllerPatch` applies over the package record and over a package patch, and wins over it. A package `Controller` file is for a model that has no bundled record, and a package `ControllerPatch` changes a bundled or packaged one. A package cannot add a `Controller` for a model that has a bundled record.

- `ojd mod install` and `ojd mod validate` refuse a package whose record or persona covers a model that your files or another package already hold. They also refuse a profile that has the ID or the name of one that you or another package already hold. The code is E4004. `--force` does not override this.
- A clash can also appear after the install, for example when you add a record later. Your file then wins. Among packages, the first by package name wins. `ojd record list` names each package record that OJD ignores and the reason. OJD does not report a package profile that it ignores because of a clash. `ojd status` and `ojd diagnose` list each persona that OJD ignores and the reason.
- A `ControllerPatch` of yours for a model that only a package defines applies over the package record. If you remove the package later, OJD lists the patch as a problem and skips it.

## Package Profiles Are Read-Only

You can activate a profile that a package ships, but you cannot change it. A change is refused with the code E3029. To change one, duplicate the profile and edit the copy.

## Manage Packages With ojd mod

These commands need no service. The running service watches the `Packages` folder in `~/Library/Application Support/OpenJoystickDriver` and applies a change without a restart.

```text
ojd mod validate FOLDER
ojd mod install FOLDER [--force] [--dry-run]
ojd mod list
ojd mod remove NAME [--force] [--dry-run]
```

- `mod validate`: Check a package folder without installing it. It checks the manifest, `requires`, the files, and clashes. It exits with code 1 and the E4xxx or E5001 code when the package is refused.
- `mod install`: Check the package and copy it to `Packages/NAME`. A package of the same name that is installed is refused with E4005 unless you pass `--force`. `--force` never overrides `requires`, a clash, or an invalid file. `--dry-run` writes nothing.
- `mod list`: List each installed package with its version, author, and files. A package that OJD does not use shows the reason with its code.
- `mod remove`: Delete only the folder of that package. It asks first on a terminal and needs `--force` otherwise. It exits with code 1 and E4006 when the package is not installed.

To try the sample package:

1. Run `ojd mod validate` with the path of the sample folder.
2. Run `ojd mod install` with the same path.
3. Run `ojd mod list` to see the files it holds.
4. Run `ojd mod remove ojd-sample` to remove it.

[Error codes](Error-Codes.md) lists E4001 to E4007. Use `ojd explain E4004` to read what a code means.

## Further Reading

- [Controller records](Controller-Records.md)
- [Profile file reference](Profile-File-Reference.md)
- [Command reference](Command-Reference.md#mod)
- [Error codes](Error-Codes.md)
