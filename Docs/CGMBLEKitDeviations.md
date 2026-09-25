# BLE provenance: what came from CGMBLEKit, what came from xDrip4iOS

Written to answer a maintainer question: *did you keep the CGMBLEKit
bluetooth handling code, or did you write your own with timers bolted on?*

Compared against `loopandlearn/CGMBLEKit` at `26ad721`.

## Short answer

The CGMBLEKit BLE code was kept. The CoreBluetooth command/condition
machinery is unmodified, the connection manager is a close port with two
deviations, and no timers were added anywhere in the BLE path.

Nothing in the BLE layer comes from xDrip4iOS.

## File-by-file

| Ours | From | Changed |
|---|---|---|
| `Transport/PeripheralManager.swift` | `PeripheralManager.swift` | **0 lines of 471** — byte-identical |
| `Transport/PeripheralManager+G5.swift` | `PeripheralManager+G5.swift` | +75 lines, **0 deletions** — purely additive |
| `Transport/TransmitterConnection.swift` | `BluetoothManager.swift` | mostly renames, 3 substantive deviations |
| `Session/TransmitterSession.swift` | `Transmitter.swift` (active path) | heavily restructured — see below |
| `Session/PassiveTransmitterSession.swift` | `Transmitter.swift` (passive path) | clean-room reimplementation — see below |

`PeripheralManager.swift` is where the connection intricacies actually live —
`runCommand`, the condition list, `commandLock`, the delegate callbacks. It
was not touched.

## Timers and delays

The entire `G6SensorCore` module contains exactly one sleep:

```swift
fileprivate func scanAfterDelay() {
    DispatchQueue.global(qos: .utility).async {
        Thread.sleep(forTimeInterval: 2)
        self.scanForPeripheral()
    }
}
```

That is CGMBLEKit's own function, byte-identical, including the two-second
sleep and its rationale.

There are **no** `Timer`, `DispatchSourceTimer`, `asyncAfter`, or polling
loops anywhere in the transport or session layer. The one `Timer` in the
whole project is a 30-second tick in the SwiftUI warm-up screen, which
refreshes displayed text and touches nothing BLE-related.

For reference, CGMBLEKit itself does use a `DispatchSourceTimer`, in
`TransmitterManager`'s simulated sample generator. That file is not vendored.

## The deviations in `TransmitterConnection`

Everything else in that file is a rename (`BluetoothManager` →
`TransmitterConnection` and its delegate methods) or added logging.

The central manager is **not** one of them: it is owned by the instance and
created exactly as CGMBLEKit creates it. An earlier revision routed every
connection through a process-wide singleton, on the theory that a second
`CBCentralManager` sharing a restoration identifier would never power on.
That was built on a misdiagnosis — the hang it was meant to fix was an
authentication timeout shorter than the transmitter's reply — and it would
have ruled out ever talking to two transmitters at once. It has been removed,
along with the teardown-and-rebuild on transmitter replacement; the session
now retargets in place and keeps its radio.

**1. Advertisement data reaches the connect decision.**
`shouldConnectPeripheral` gained an `advertisementData` parameter, so the
match can fall back to `CBAdvertisementDataLocalNameKey` when
`peripheral.name` is nil at discovery.

**2. Peripheral identifier is reported upward.** A new
`didUpdatePeripheralIdentifier` delegate call lets the identifier be
persisted and passed back into `init`, so a known transmitter can be
reconnected directly across launches.

**3. Unsolicited control and authentication values reach the delegate.**
CGMBLEKit routes them to `Transmitter`'s passive listener. Here they were
initially dropped (only backfill was forwarded); passive mode re-adds two
delegate callbacks, `didReceiveControlResponse` and
`didReceiveAuthenticationResponse`. Values claimed by the condition
machinery — an active session's own request/response traffic — still never
reach these callbacks.

Also: the configuration constant changed from `.dexcomG5` to `.dexcomG6`, and
the authentication-response delegate callback was dropped because auth
responses are now awaited inline (below).

## Timeouts

CGMBLEKit's per-command default is 2 seconds. We kept it everywhere except:

| Operation | CGMBLEKit | Ours | Why |
|---|---|---|---|
| Auth exchange | 2s (default) | **10s** | See below |
| Control notify while pairing | 15s | **60s** | The user has to tap Pair on the iOS prompt |
| Backfill request | — | **30s** ack, **5s** frame top-up | No equivalent upstream; backfill is passive there |
| Everything else | 2s | 2s | unchanged |

The auth timeout is the one worth scrutiny. Field logs show the transmitter
holding the connection open for about 15 seconds, and auth replies arriving
after more than two seconds under load — so the exchange was being abandoned
while the reply was still in flight and reported as a protocol failure. Ten
seconds sits inside the window the transmitter offers while leaving room for
the rest of the flow. Note CGMBLEKit itself already uses a 15-second timeout
when subscribing to the control characteristic (`Transmitter.swift:523`), so
a wait longer than the 2s default is not unprecedented upstream.

## The auth exchange

CGMBLEKit does write-then-read:

```swift
try writeMessage(authMessage, for: .authentication)          // void variant
authResponse = try readMessage(for: .authentication)         // separate wait
```

Ours does a single call that registers the value-update condition before the
write and content-matches the reply:

```swift
authResponse = try writeMessage(
    authMessage, for: .authentication,
    expecting: AuthRequestRxMessage.self,
    matching: { $0.tokenHash == expectedTokenHash },
    timeout: TransmitterSession.authTimeout)
```

To be fair to upstream: CGMBLEKit's own `writeMessage` already registers the
value-update condition before the write when the characteristic is notifying.
We did not invent that pattern — we applied it to auth, added an explicit
expected-response type and a content predicate, and made non-matching values
fail to satisfy the condition instead of being accepted (they are logged in
hex). This matters because the auth characteristic is write + indicate only:
`readValue` on it returns `CBATTError.readNotPermitted`, and a stale value
left on the characteristic could otherwise satisfy a bare type match.

## The session layer

`TransmitterSession` is where the real divergence is, and it is policy rather
than connection handling. It covers the **active** path only; the passive
path is a separate class (below).

- **Removed:** the passive path from this class (it lives in
  `PassiveTransmitterSession` now). Also gone:
  `resumeScanning`, `stopScanning`, `transmitterDidConnect`; `computeHash`
  moved to `TransmitterID`.
- **Added:** `start`/`stop`/`retarget`, `requestBackfill`/`drainBackfill`,
  `readBatteryStatus`.
- **Kept:** `authenticate`, `requestBond`, `enableNotify`,
  `listenToCharacteristic` (moved to `PeripheralManager+G5.swift`, shared
  with the passive session), `sendCommand`, `dequeuePendingCommand`,
  `readGlucose`, `readTimeMessage`, `readCalibrationData`,
  `readTransmitterVersion`, `disconnect`.

Backfill is a request in the active session. In CGMBLEKit backfill arrives as
notifications and there is no request function, because the Dexcom app drives
the session.

## The passive session

`PassiveTransmitterSession` + `PassiveMessageHandler` reimplement CGMBLEKit's
passive path without its accumulated workarounds:

- **Subscribing is done once, at connect, for all three characteristics**
  (authentication, control, backfill), and subscriptions are never toggled
  for the life of the connection. CGMBLEKit subscribes to control only after
  observing an authenticated session (commit `dec4ff0`), because toggling
  subscriptions mid-exchange confused CoreBluetooth — a workaround this
  design sidesteps rather than replicates. If field testing shows missed
  traffic, the fallback is to gate the control subscription on the observed
  `AuthChallengeRxMessage`, which the handler already parses.
- **No writes exist in scope at all** — no auth, bond, commands, active reads
  or disconnect request. CGMBLEKit's passive path shares a class with the
  active path, so writes were reachable from it.
- Message handling is a pure type (`PassiveMessageHandler`, no CoreBluetooth)
  that turns observed frames into events, so the whole decode path —
  time-frame caching, glucose dating, backfill frame reassembly and CRC
  validation against the observed acknowledgement — is unit-tested.

## What came from xDrip4iOS

Four things, none of them code, none in the BLE layer:

1. **Anubis detection** — a 180-day expiry in the version-rx frame indicates
   an Anubis-modded transmitter; stock reports 90.
2. **Session response codes** — the meanings of the start/stop reply bytes.
3. **Sensor code → calibration parameter table** (cross-checked against
   xDrip+ on Android).
4. **Per-connection flow ordering** — request backfill after glucose, let the
   frames stream in behind the remaining reads, decode before disconnecting.
   Our first attempt read the buffer immediately after the acknowledgement,
   found it empty and tore the link down, so backfill never worked at all.

These are byte layouts, opcode meanings and observed sequencing. No source
was copied, and the project is MIT with xDrip4iOS's GPL-3.0 treated as
reference-only. Credit for the protocol itself belongs further back — Nathan
Racklyeft and Pete Schwamb first, then others; xDrip4iOS is where a good deal
of it is written down, not where it was worked out.

**Explicitly not taken:** xDrip4iOS's event-driven connection model. It was
considered and rejected in favour of porting CGMBLEKit's `BluetoothManager`.

## Naming confusion worth flagging

Grepping this repo for `xdrip` returns 44 files, which looks alarming. 41 of
those are CGMBLEKit's own original headers — CGMBLEKit was named `xDripG5` /
`xDrip5` before it moved under LoopKit, and those headers were preserved
along with their copyright lines. Only 4 files reference Johan Degraeve's
GPL `xdripswift` / xDrip4iOS, and all 4 are the items listed above.
