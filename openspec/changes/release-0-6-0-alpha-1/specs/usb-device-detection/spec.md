## Purpose

Controllers served by the XboxUSBDevice DriverKit extension are found and bound to their protocol family.

## ADDED Requirements

### Requirement: REQ-24 Original Xbox One controller is listed

An original Xbox One controller (`045E:02D1`, model 1537) MUST be listed by `ojd controller list` and bound to `xbox.gip` when the XboxUSBDevice extension is active, or the cause MUST be recorded with evidence in `docs/testing/` and in `wiki/Known-Issues.md` when it is outside OJD's code.

#### Scenario: Extension active

- **WHEN** a `045E:02D1` controller is connected and the XboxUSBDevice extension is active
- **THEN** `ojd controller list` lists it bound to `xbox.gip`

#### Scenario: Cause outside OJD

- **WHEN** the cause is outside OJD's code
- **THEN** `docs/testing/` and `wiki/Known-Issues.md` record it with evidence
