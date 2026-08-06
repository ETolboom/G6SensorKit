# G6SensorKit

A [LoopKit](https://github.com/LoopKit/LoopKit) CGMManager plugin that connects
**directly and natively** to Dexcom G6 and Dexcom ONE transmitters over
Bluetooth — an owning, active connection (authentication, session start/stop,
sensor codes, calibration, backfill), usable by both
[Loop](https://github.com/LoopKit/Loop) and [Trio](https://github.com/nightscout/Trio)
from this single repository.

> **Status: pre-alpha, under active development. Do not use for therapy.**

## What "native" means

Unlike existing drivers that passively read alongside the official Dexcom app,
G6SensorKit *owns* the transmitter relationship: it performs the authentication
handshake keyed on the transmitter ID, starts and stops sensor sessions
(including 4-digit sensor codes), sends calibrations, and backfills missed
readings after connectivity gaps. The official Dexcom app must **not** be used
at the same time.

Supported: Dexcom G6 (`8…` transmitter IDs), Dexcom ONE (`5…`/`C…`), and
Anubis-modified G6 transmitters (auto-detected, extended session length).
Not supported: Dexcom G5 (`4…` IDs — no longer in circulation), G7/ONE+
(see [G7SensorKit](https://github.com/LoopKit/G7SensorKit)).

## Layout

| Target | Role |
|---|---|
| `G6SensorCore` (SwiftPM) | LoopKit-free transport/protocol core: BLE, auth, messages, session state machine |
| `G6SensorKit.framework` | LoopKit `CGMManager` conformance, state persistence, sample conversion |
| `G6SensorKitUI.framework` | `CGMManagerUI`, onboarding and settings UI |
| `G6SensorKitPlugin.loopplugin` | Plugin bundle discovered by Loop at runtime |
| `Apps/G6SensorHarness` | Standalone proof-of-concept app exercising the core on a live transmitter |

## License

MIT — see `LICENSE`. Portions adapted from
[CGMBLEKit](https://github.com/LoopKit/CGMBLEKit) (MIT).

"Dexcom", "G6", and "ONE" are trademarks of Dexcom, Inc., used only to describe
compatibility. This project is not affiliated with or endorsed by Dexcom.

## Safety

This software is not a medical device and nothing here is medical advice.
Follow your device's instructions for use and consult your care team. Alerts
depend on the host app's alert pipeline (Trio requires the `dev`-branch alert
pipeline or later). Always maintain at least one independent alerting path.
