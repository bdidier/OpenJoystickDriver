# SDK Endpoint

The endpoint is a local socket where a program that you grant reads controller events and drives a virtual gamepad. This page is the reference for the messages, the errors, the grants, and the versions. For the steps that a user follows, see [Automating OpenJoystickDriver](../../wiki/Automating-OpenJoystickDriver.md). For the design decisions, see [Public Endpoint Design](../development/public-endpoint-design.md).

## Contents

- [Connect](#connect)
- [Handshake](#handshake)
- [Messages](#messages)
- [Errors](#errors)
- [AccessGrants](#accessgrants)
- [Versioning](#versioning)
- [Reference client](#reference-client)

## Connect

1. Turn on the endpoint: `ojd access enable`. It is off by default.
2. Grant your program, by its signature or by a token. See [AccessGrants](#accessgrants).
3. Read the socket path: `ojd --json access status | jq -r .socketPath`. The socket exists only while the endpoint is on. Another transport, a WebSocket on `127.0.0.1`, carries the same messages: one JSON object in each text message.

The program and the endpoint exchange JSON objects, one per line, each at most 64 KiB. [`endpoint.schema.json`](../../Resources/Schemas/endpoint.schema.json) describes each line: `#/$defs/clientLine` for the lines that a program sends, and `#/$defs/serviceLine` for the lines that the endpoint sends.

## Handshake

1. The endpoint sends a `Challenge` first.
2. Within 5 seconds, the program sends a `Hello` with the scopes that it needs. A program that a signature grants sends only the scopes. A program that a token grants also sends `tokenName` and `proof`.
3. The endpoint answers a `Welcome` with the scopes that it granted, or a `Status` failure, and then closes the connection.
4. The program sends one request: a `Subscription` to read, or a `FeedRequest` to drive a virtual gamepad. A `FeedRequest` needs the `control` scope.
5. A subscription gets watch lines. A feed gets a `FeedSession`, and then the program sends `Frame` lines.

A connection that sends a line at the wrong point gets `E1011`. The endpoint serves at most 8 socket connections and 8 WebSocket connections at the same time. When a program reads too slowly, the endpoint keeps only the newest `MODIFIED` line of each controller. When 256 lines wait, it sends `E1007` and closes the connection.

### Token proof

A program with a token does not send the token. It proves that it has the token by signing the challenge:

1. Join four lines, each ending with a newline: `OpenJoystickDriver endpoint hello 1`, the challenge's `nonce`, the origin of the page, and the port of the WebSocket. On the socket, the origin and the port lines are empty.
2. Compute the HMAC-SHA256 of those lines, keyed with the SHA-256 of the token.
3. Write the result as lowercase hex in `proof`.

## Messages

Every line that the endpoint sends, except a watch line, and every line that a program sends has `apiVersion` and `kind`. The examples validate against the schema.

### Challenge

The endpoint sends it first on each connection. `nonce` is 32 random bytes in unpadded base64url, new for each connection.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Challenge","nonce":"ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8"}
```

### Hello

The program sends it once, after the `Challenge`. `scopes` lists the scopes that the program needs: `read`, `control`, or both. Each must be granted.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Hello","scopes":["read"]}
```

With a token, add `tokenName` and `proof`:

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Hello","scopes":["control"],"tokenName":"driver","proof":"2ea98b640f249c35c5644ae64b42d56812ec40516475aa62913b53b80e9551c9"}
```

### Welcome

The endpoint answers a valid `Hello` with the OpenJoystickDriver `version` and the granted `scopes`.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Welcome","version":"0.6.0-alpha.1","scopes":["read"]}
```

### Subscription

The program sends it after the `Welcome` to read the controllers. `controllers` is the only stream. Add `"output":true` for the values of the virtual gamepad in the watch lines.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Subscription","stream":"controllers"}
```

The endpoint answers with the same `ADDED`, `MODIFIED`, and `DELETED` watch lines as `ojd controller watch --all --json`: first the connected controllers, then each change. A watch line has `type` and `object`, and it has no `apiVersion`. The `object` has the `kind` `Controller`.

```json
{"type":"ADDED","object":{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Controller","id":"pad-1","name":"Test Pad","vendorID":1118,"productID":654,"connection":"usb","hasSerialNumber":false,"protocol":"xbox.xbox360","session":"active"}}
```

### FeedRequest

The program sends it after the `Welcome` to publish a virtual gamepad. It needs the `control` scope. `as` is a persona id: `Generic` or `SdlCompatible`. Closing the connection removes the virtual gamepad.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"FeedRequest","as":"Generic"}
```

### FeedSession

The endpoint answers a `FeedRequest` when the virtual gamepad exists.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"FeedSession","as":"Generic"}
```

### Frame

After the `FeedSession`, the program sends one `Frame` for each line. A frame has the keys of an `ojd virtual feed` line. A control that the frame omits is neutral. Sticks run from -1 to 1, with positive Y up, and triggers run from 0 to 1. `holdMilliseconds` is how long the frame shows at least; without it, the frame shows until the next one.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Frame","buttons":["south"],"axes":{"left_stick_y":0.5},"holdMilliseconds":100}
```

The service shows the frames in order, each for at least 8 ms. While 256 frames wait, the endpoint stops reading lines. The endpoint does not report when a frame has played, so the program stays connected until its last frame has played, because closing the connection drops the frames that wait. When the program sends no frame line for 2 seconds after its last frame has played, the endpoint closes the connection with `E1009`. The endpoint runs at most 4 virtual gamepads at the same time and answers another `FeedRequest` with `E1008`.

### RumbleCommand

The endpoint sends each rumble command that a game sends to the virtual gamepad. `type` is `setRumble` or `stopRumble`. The intensities run from 0 to 65535.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"RumbleCommand","type":"setRumble","intensities":{"leftMain":65535,"rightMain":0,"leftTrigger":0,"rightTrigger":0,"leftHaptic":0,"rightHaptic":0},"durationMilliseconds":200}
```

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"RumbleCommand","type":"stopRumble"}
```

### Status

The endpoint sends a `Status` when it refuses a line or ends the connection. `status` is `Failure`, `code` is an [error code](#errors), and `message` is English text for logs. Branch on `code`, not on `message`.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Status","status":"Failure","code":"E1008","message":"The endpoint runs 4 virtual gamepads already."}
```

With `E1010`, `E1011`, and `E1012`, `details.supportedAPIVersions` lists the `apiVersion` values that the endpoint accepts.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"Status","status":"Failure","code":"E1010","message":"The apiVersion is not supported.","details":{"supportedAPIVersions":["openjoystickdriver/v1alpha1"]}}
```

## Errors

An error is a `Status` line, and then the endpoint closes the connection. Each code is stable. Look up the cause and the fix of a code with `ojd explain E1002`, or on [Error codes](../../wiki/Error-Codes.md).

| Code | Name | Meaning |
| --- | --- | --- |
| `E1001` | `endpointDisabled` | The endpoint is off, or its WebSocket is off. |
| `E1002` | `notGranted` | The program, or its token, has no grant for the scopes in the `Hello`. |
| `E1003` | `unsupportedProtocol` | Retired in 0.6.0-alpha.1. `E1010` replaced it. |
| `E1004` | `invalidMessage` | The line is not valid for its `kind`. |
| `E1005` | `tooManyConnections` | The endpoint serves the maximum number of connections. |
| `E1006` | `revoked` | A user revoked the grant while the connection was open. |
| `E1007` | `tooSlow` | The program reads too slowly, and 256 lines wait. |
| `E1008` | `tooManyFeeds` | The endpoint runs the maximum number of virtual gamepads. |
| `E1009` | `feedClosed` | The virtual gamepad closed: it did not start, the service stopped it, or the program sent no frame line in time. |
| `E1010` | `unsupportedEndpointVersion` | `apiVersion` is a string that the endpoint does not accept. |
| `E1011` | `unexpectedKind` | `kind` is unknown, or the endpoint does not accept it at this point. |
| `E1012` | `missingHeader` | `apiVersion` or `kind` is missing, `null`, or not a string. |

A program must not guess a version. On `E1010`, `E1011`, or `E1012`, it reads `details.supportedAPIVersions`, and it either speaks one of those versions or reports them and stops.

## AccessGrants

The endpoint serves a program only when `AccessGrants` has a grant for it. Only the service writes the file `AccessGrants.json` in the OpenJoystickDriver Application Support folder, when `ojd access` runs, so a revoke takes effect at once. [`access-grants.schema.json`](../../Resources/Schemas/access-grants.schema.json) describes the file. A program without a grant gets `E1002`.

- A grant by signature (`grants`) names the signing identifier and the team of the program. Ad-hoc signed and unsigned programs are refused. Create it with `ojd access grant PATH`.
- A grant by token (`tokens`) names the token and stores only its SHA-256, so the token cannot be shown again. It can limit the web `origins`. A token with `origins` cannot have `control`. Create it with `ojd access grant --token NAME`.
- `scopes` is `read` to receive controller events, `control` to drive a virtual gamepad, or both. A grant with `control` also records when `control` was granted, in `controlGrantedAt`.
- `web` holds the switch and the port of the WebSocket.

The file is a secret, because the hashes are the keys of the proofs. The service writes it with mode 0600. Keep it out of shared reports and backups.

```json
{"apiVersion":"openjoystickdriver/v1alpha1","kind":"AccessGrants","enabled":true,"grants":[{"kind":"team","identifier":"com.example.overlay","teamIdentifier":"ABCDE12345","scopes":["read"],"grantedAt":"2026-01-01T00:00:00Z","path":"/Applications/Overlay.app"}],"tokens":[{"name":"driver","tokenSHA256":"0000000000000000000000000000000000000000000000000000000000000000","origins":[],"scopes":["control"],"grantedAt":"2026-01-01T00:00:00Z","controlGrantedAt":"2026-01-01T00:00:00Z"}],"web":{"enabled":false,"port":49152}}
```

## Versioning

The `apiVersion` of the endpoint is `openjoystickdriver/v1alpha1`. It is the same value that the schemas and the user files use. The endpoint accepts exactly the versions in `details.supportedAPIVersions`, today only this one.

- The endpoint does not translate between versions. A line with another `apiVersion`, such as the old `openjoystickdriver.io/v1beta1`, gets `E1010` with the supported list.
- An alpha version can change without a compatibility promise. The release notes list each change.
- A change that older programs cannot read gets a new `apiVersion`. Error codes and persona ids do not change meaning: a retired code stays in the catalog, and `ojd explain` still resolves it.
- Persona ids in `as` are `Generic` and `SdlCompatible`. They name no operating system.

## Reference client

[`Scripts/SDK/reference_client.py`](../../Scripts/SDK/reference_client.py) is the reference client. It uses only the Python standard library, and the repository does not install or package it: copy it into your project. Set `OJD_TOKEN` to the token that `ojd access grant --token driver` printed:

```shell
OJD_TOKEN=ojd_… python3 Scripts/SDK/reference_client.py watch
OJD_TOKEN=ojd_… python3 Scripts/SDK/reference_client.py feed
```

- `watch` subscribes to the `controllers` stream and prints the first watch line. `--count N` prints `N` lines. `--timeout SECONDS` ends the run with a non-zero exit when the endpoint sends nothing for that long, for example when no controller is connected.
- `feed` presses the south button for 100 ms, prints the rumble commands that the endpoint sends, and stays connected until the release has played.
- On `E1010`, `E1011`, or `E1012`, or when a line has another `apiVersion`, the client stops and reports the supported versions.
- `--socket PATH` names the socket; without it, the client runs `ojd --json access status`.

The test `EndpointReferenceClientTests` runs the client against a real endpoint server: the client subscribes and receives a watch line, and it feeds a frame to a virtual gamepad.
