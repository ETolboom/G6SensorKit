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

## Safety notes for host maintainers

- G6SensorKit owns the transmitter connection. Users must not run the
  manufacturer's app against the same transmitter.
- The manufacturer's app is not watching glucose while this driver is in use,
  so high/low alerting is entirely the host's responsibility. Do not ship this
  plugin in a host without working glucose alerts.
- `providesBLEHeartbeat` is `true`. In Loop this suppresses the pump's timer
  tick, so regressions in BLE wake-up affect loop cadence, not just CGM data.
