## ADDED Requirements

### Requirement: Source and sink boundary

Input SHALL flow through an `InputSource` that produces canonical frames and an `OutputSink` that consumes them. Physical controllers, the virtual HID device, the endpoint and network transports SHALL attach only through these two protocols.

#### Scenario: New transport

- **WHEN** a transport is added
- **THEN** it implements `InputSource` or `OutputSink` and no other part of the pipeline changes

### Requirement: WebRTC bridge

OJD SHALL ship WebRTC as a separate program, the WebRTC bridge, that is a client of the SDK endpoint. The app, the service and `ojd` SHALL NOT link WebRTC code. Endpoint grants SHALL govern the bridge like any other client.

#### Scenario: Core without WebRTC

- **WHEN** the app, the service and `ojd` are built
- **THEN** none of them links a WebRTC library

#### Scenario: Not granted

- **WHEN** the bridge has no grant
- **THEN** the endpoint refuses it with `E1002` and no virtual gamepad appears

### Requirement: Bridge roles

On the Mac that runs the game, the bridge SHALL take canonical frames from a remote peer over a WebRTC data channel, drive a virtual gamepad with a `FeedRequest`, and send each `RumbleCommand` back to the peer. On the player's Mac, it SHALL read a controller with a `Subscription` and send its frames to the peer. It SHALL exchange the offer and answer out of band and SHALL NOT open a listening socket.

#### Scenario: Remote play

- **WHEN** the user grants the bridge the `control` scope and a remote peer connects
- **THEN** the game receives the peer's input and the peer receives rumble

#### Scenario: No listener

- **WHEN** the bridge runs
- **THEN** a socket scan shows no listening socket owned by it

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
