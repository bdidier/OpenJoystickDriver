## MODIFIED Requirements

### Requirement: REQ-23 Virtual stick reports are not delayed or held

The virtual gamepad MUST deliver each change of a stick axis to the system without being dropped, held behind a previous value, or delayed by OJD's own queueing, and a test MUST reproduce the cause that is found and show the fix.
The queue capacity is the `tuning.frameQueueCapacity` value of the controller's record, else the `defaults.tuning` value of its protocol description, else 64, and the requirement applies to every persona, `Generic` and `SDLCompatible`.

#### Scenario: Burst of stick reports with a slow send

- **WHEN** stick reports arrive faster than the virtual device accepts them, for each persona
- **THEN** the newest stick state is delivered within one send time, with no stale value delivered before it
- **AND** every button edge is still delivered
