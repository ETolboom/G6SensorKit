# Host integration

G6SensorKit ships from one repository for both hosts, but the two hosts load
CGM plugins differently: **Loop discovers plugin bundles at runtime**, while
**Trio links CGM frameworks statically**. The repository satisfies both — Loop
consumes `G6SensorKitPlugin.loopplugin`, and Trio links the two frameworks and
ignores the plugin bundle.

Regenerate the Xcode project after adding or moving source files:

```sh
gem install xcodeproj
ruby Scripts/generate_project.rb
```

The project links `LoopKit.framework` and `LoopKitUI.framework` from
`BUILT_PRODUCTS_DIR`, so it only builds inside a host workspace that also
builds LoopKit.

## Loop (LoopWorkspace)

No changes to Loop's own source are required.

1. Add the submodule to `LoopWorkspace`:
   ```sh
   git submodule add https://github.com/nightscout/G6SensorKit.git G6SensorKit
   ```
2. Add `G6SensorKit/G6SensorKit.xcodeproj` as a FileRef in
   `LoopWorkspace.xcworkspace/contents.xcworkspacedata`.
3. Add a `BuildActionEntry` for `G6SensorKitPlugin.loopplugin` to the
   `LoopWorkspace` scheme, **before** `Loop.app` — `copy-plugins.sh` reads
   `BUILT_PRODUCTS_DIR`, so the plugin must already be built.
4. Build the **LoopWorkspace** scheme (not the Loop scheme; the latter builds
   no plugins). `Loop/Scripts/copy-plugins.sh` renames the bundle to
   `.framework` inside `Loop.app/Frameworks`, hoists the embedded frameworks
   flat, and re-signs them.
5. The CGM picker lists "Dexcom G6 / ONE (native)" from the plugin's
   Info.plist without loading any code.

Nothing needs adding to Loop's entitlements: `bluetooth-central` is a host-app
background mode that the plugin inherits (Loop already declares it), and
`copy-plugins.sh` preserves entitlements on re-sign, so a plugin cannot add
its own.

A malformed plugin makes Loop call `fatalError` rather than skipping it, so CI
must build the plugin against the exact LoopWorkspace pin.

## Trio (`dev` branch)

Base all Trio work on **`dev`**. Trio's `dev` branch routes plugin-issued
alerts through `TrioAlertManager` and reads `providesBLEHeartbeat`; its older
`main` branch did neither, so G6SensorKit's expiry, failure, and signal-loss
alerts would be discarded there.

1. Add the submodule and a FileRef for `G6SensorKit.xcodeproj` in
   `Trio.xcworkspace`.
2. In `Trio.xcodeproj`, link **and embed** `G6SensorKit.framework` and
   `G6SensorKitUI.framework` with `CodeSignOnCopy` + `RemoveHeadersOnCopy` —
   the same shape Trio already uses for the G7SensorKit pair. The
   `.loopplugin` bundle is unused by Trio.
3. Register the manager in `Trio/Trio/Sources/APS/PluginManager.swift`:
   ```swift
   import G6SensorKit
   import G6SensorKitUI
   // …
   CgmPluginDescription(
       pluginIdentifier: G6CGMManager.pluginIdentifier,
       localizedTitle: String(localized: "Dexcom G6 / ONE (native)"),
       manager: G6CGMManager.self
   )
   ```
4. Confirm the CGM manager is registered with `TrioAlertManager` as an
   `AlertResponder`/`AlertSoundVendor` so acknowledgements reach
   `acknowledgeAlert` (Trio registers the pump this way in
   `DeviceDataManager`; verify the CGM path).

## LoopKit fork differences

Three LoopKit API generations exist across this ecosystem: upstream `dev`
(`HKQuantity`, completion-handler `acknowledgeAlert`, three-argument
`CGMManagerStatus`), the tidepool-sync fork (`LoopQuantity`, `async`
`acknowledgeAlert`, five-argument status), and Trio's `loopandlearn` pin.

G6SensorKit currently targets the upstream-`dev`-shaped API, verified by
building against `LoopKit/LoopKit`. Fork differences belong in `Common/`
shims — never in `G6SensorCore`, which imports no LoopKit at all. A CI matrix
building against both hosts at pinned SHAs is the only reliable guard.

## Connection modes

The manager runs in one of two modes, persisted as `passiveModeEnabled` in the
manager state, chosen during onboarding and switchable afterwards under
Transmitter details:

- **Direct (default)**: G6SensorKit owns the transmitter — authentication,
  bonding, session start/stop, calibrations, active backfill requests. The
  manufacturer's app must not be connected to the same transmitter.
- **Passive**: G6SensorKit never writes to the transmitter. It subscribes to
  the authentication/control/backfill characteristics and decodes the traffic
  of the session the manufacturer's app (or another bonded client on the same
  phone) drives. Session commands, calibrations, battery reads and backfill
  requests are unavailable; `enqueue(_:)` drops commands.

`providesBLEHeartbeat` is `true` in direct mode and `false` in passive mode:
in passive the manufacturer's app drives the cadence, so the host's own fetch
timer must keep ticking.

## Migration from CGMBLEKit

`G6CGMManager.init?(rawState:)` accepts a rawState dictionary persisted by
CGMBLEKit's `TransmitterManagerState` directly. A state is recognized as
CGMBLEKit-shaped when `passiveModeEnabled` and `sensorLifeDays` are both
absent (every G6SensorKit state carries both). Legacy key handling:

| CGMBLEKit key | Handling |
|---|---|
| `transmitterID` | Required, same key |
| `transmitterStartDate` | Same key |
| `sensorStartOffset` (seconds since activation) | Mapped to `sensorStartDate = transmitterStartDate + offset` |
| `transmitterExpiryInDays` | Same key (Int) |
| `shouldSyncToRemoteService` | Same key |
| *(absent)* | `passiveModeEnabled = true`, `isOnboarded = true` — CGMBLEKit ran passive-only, so migrated users keep exactly the behavior they had and never see onboarding |

`peripheralIdentifier` starts nil and is learned on first connection, so the
first launch after migration does one name-filtered scan.

## Safety notes for host maintainers

- In direct mode G6SensorKit owns the transmitter connection. Users must not
  run the manufacturer's app against the same transmitter. In passive mode the
  manufacturer's app is **required** on the same phone.
- The manufacturer's app is not watching glucose while this driver is in use
  in direct mode, so high/low alerting is entirely the host's responsibility.
  Do not ship this plugin in a host without working glucose alerts.
- `providesBLEHeartbeat` is `true` in direct mode. In Loop this suppresses
  the pump's timer tick, so regressions in BLE wake-up affect loop cadence,
  not just CGM data.
