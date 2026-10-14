## ADDED Requirements

### Requirement: Source and sink boundary

Input SHALL flow through an `InputSource` that produces canonical frames and an `OutputSink` that consumes them. Physical controllers, the virtual HID device, the endpoint and network transports SHALL attach only through these two protocols.

#### Scenario: New transport

- **WHEN** a transport is added
- **THEN** it implements `InputSource` or `OutputSink` and no other part of the pipeline changes

### Requirement: WebRTC transport

OJD SHALL provide WebRTC as one transport, using the endpoint `Subscription` flow for signalling, carrying canonical frames and returning rumble. The transport SHALL be off until the user enables it with a setting.

#### Scenario: Remote play

- **WHEN** a remote peer connects after the user enables the transport and grants access
- **THEN** the peer receives frames and can send rumble

#### Scenario: Disabled

- **WHEN** the setting is off
- **THEN** no listening socket is open for the transport

### Requirement: Queue policy

Frame queues SHALL have a bounded policy declared per record or default (for example newest-wins), so slow consumers cannot grow memory.

#### Scenario: Slow consumer

- **WHEN** a consumer reads slower than the controller reports
- **THEN** memory stays bounded and the newest frames arrive

### Requirement: Latency reporting

`ojd` SHALL expose per-stage frame timestamps for diagnosis, so stutter reports can be measured.

#### Scenario: Diagnose

- **WHEN** the user runs `ojd diagnose` while streaming
- **THEN** the report lists dispatch and delivery timestamps
