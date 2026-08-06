# G6SensorHarness

Standalone proof-of-concept app that drives `G6SensorCore` against a live
Dexcom G6 / ONE transmitter, with no Loop or Trio build required. Use it to
validate the BLE port — pairing, the ~5-minute connect/read/disconnect cycle,
background wake and state restoration, session start/stop with sensor codes,
calibration, and backfill — before host integration.

## Generate and run

```sh
brew install xcodegen
xcodegen -s Apps/G6SensorHarness/project.yml
open Apps/G6SensorHarness/G6SensorHarness.xcodeproj
```

Select your development team, run on a real device (BLE is unavailable in the
simulator), enter the 6-character transmitter ID, and tap Start. The first
connection triggers an iOS pairing prompt that must be accepted within about
60 seconds.

The in-app log records every connection, read, command result, and error so
background behavior can be inspected without attaching a debugger.

**The official Dexcom app must not be connected to the same transmitter while
testing.** This is not a medical device; do not use it for therapy decisions.
