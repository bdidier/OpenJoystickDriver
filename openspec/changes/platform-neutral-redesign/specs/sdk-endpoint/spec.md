## ADDED Requirements

### Requirement: Public endpoint

The service SHALL expose a local endpoint that speaks `openjoystickdriver/v1alpha1` messages (Challenge, Hello, Welcome, Subscription, FeedRequest, FeedSession, Frame, Status), documented in `docs/sdk/` and described by `endpoint.schema.json`. Access SHALL need a grant from `AccessGrants`.

#### Scenario: No grant

- **WHEN** a client connects without a grant
- **THEN** the endpoint answers with an error code and closes

### Requirement: Version negotiation

A client sending an unsupported `apiVersion` SHALL receive an error that lists the supported versions.

#### Scenario: Old client

- **WHEN** a client sends `openjoystickdriver.io/v1beta1`
- **THEN** the error lists `openjoystickdriver/v1alpha1`

### Requirement: Reference client

The repository SHALL ship a reference client and a test that runs it against the endpoint.

#### Scenario: Round trip

- **WHEN** the reference-client test runs
- **THEN** it subscribes and receives a watch line with the controller's input state

### Requirement: Error catalog

Endpoint errors SHALL come from the error catalog with stable codes. New codes SHALL be added for unsupported version, wrong kind and missing header.

#### Scenario: Code stability

- **WHEN** the catalog is regenerated
- **THEN** existing codes keep their numbers

### Requirement: Neutral naming

Endpoint messages SHALL use persona ids and neutral vocabulary and SHALL NOT expose OS-specific names outside `platform`.

#### Scenario: Persona field

- **WHEN** a Status message names a persona
- **THEN** it uses `Generic` or `SdlCompatible`
