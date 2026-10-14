# virtual-input-delivery Specification

## Purpose

The virtual gamepad delivers each input change to the system without delay or stale values.

## Requirements

### Requirement: REQ-23 Virtual stick reports are not delayed or held

The virtual gamepad MUST deliver each change of a stick axis to the system without being dropped, held behind a previous value, or delayed by OJD's own queueing, and a test MUST reproduce the cause that is found and show the fix.

#### Scenario: Burst of stick reports with a slow send

- **WHEN** stick reports arrive faster than the virtual device accepts them
- **THEN** the newest stick state is delivered within one send time, with no stale value delivered before it
- **AND** every button edge is still delivered
