# Wire Protocols

OJD classifies physical pads by host wire protocol, not by consumer API. XInput, DirectInput, SDL, and `GCController` are consumers of a virtual HID device.

| Family | Official name | USB identity | Linux | Windows | macOS 12+ without SIP |
| --- | --- | --- | --- | --- | --- |
| XID | Xbox Input Device | class `'X'/'B'/0` | `xpad` `XTYPE_XBOX` | no inbox driver | IOUSBHost if the kernel leaves the interface; userspace XID parser; virtual HID |
| XUSB | [MS-XUSBI](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-xusbi/c0beb1e6-054f-4e2c-b6c3-7b5dff1299a5) | `FF/5D/01` wired (Krypton), `FF/5D/81` wireless adapter (Argon) | `XTYPE_XBOX360` / `XTYPE_XBOX360W` | `XUSB22.sys` | IOUSBHost userspace; virtual HID |
| GIP | [MS-GIPUSB](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gipusb/e7c90904-5e21-426e-b9ad-d82adeee0dbc) | `FF/47/D0` | `XTYPE_XBOXONE` | `xboxgip.sys` | IOUSBHost, or entitled DEXT for Apple-approved Microsoft pairs; virtual HID |
| HID | USB/Bluetooth HID | class `03` | `hid-sony`, `hid-playstation`, `hid-nintendo`, `hid-steam`, Generic | `hidclass.sys` | `IOHIDManager` / `IOHIDDevice`; virtual HID |

Xbox One S 1708+ Bluetooth is HID, not USB GIP. DualShock 1/2 used the PlayStation controller-port serial bus, not USB HID.

Every family publishes through `VirtualHIDProfileSelector`, which picks one of exactly two virtual profiles per controller: `SdlCompatible` (`045E:02FD`, the Bluetooth-style Xbox One S layout) when the controller's primary controls fit it, else `Generic` (`1209:4A4F`, input-only). A per-model Advanced override can pin either profile; selection falls back to automatic when the controller can't satisfy the override. Catalog membership still comes from pinned Linux sources, HID tables, and local overrides. Apple GameController MobileAsset is diagnostic evidence, not the support catalog.

Each published device owns a host-report handler. Event reports and host-protocol replies use one ordered sender (a 64-entry queue and a two-second native send deadline). Suppression neutralizes the published input; closing rejects queued work and drains the current native send before releasing the device.

Native SetReport buffers follow IOKit/HIDAPI framing: numbered reports include the report ID at byte zero; unnumbered reports contain only data. The internal request type also accepts explicitly marked ID-less payloads, never guessing framing from contents. GetReport returns a complete report bounded by the caller's positive capacity. Unsupported type/ID combinations and malformed requests fail with native IOKit errors.

GetReport answers only the input report that the virtual format declares, bounded by the caller's capacity. SetReport decodes one output report: the Xbox One rumble report (ID `03`, eight payload bytes) of `SdlCompatible`. `Generic` is input-only. Any other type or ID is unsupported and an incorrectly sized payload is malformed. No virtual session answers Sony or Nintendo feature reports or commands; the Sony and Nintendo drivers speak those protocols to the physical controller only. Report IDs in this paragraph are hexadecimal.

Codec and concurrency tests cover these contracts. They do not establish signed SDL/GameController binding, TCC reopen behavior, or physical output delivery.

Build with SwiftPM; neither Xcode.app nor disabling SIP is required.
