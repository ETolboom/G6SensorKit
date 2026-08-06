# Contributing to G6SensorKit

Thanks for helping. One rule matters more than anything else here, because
this code talks to a medical device.

## Safety-relevant behavior and wording are not free to change

- Do not widen what counts as a usable reading. The transmitter's algorithm
  state governs; warm-up, stopped, and failure states must not produce
  glucose samples.
- Do not remove or soften the safety caveats in the onboarding and settings
  copy (warm-up, do-not-dose-on-early-readings, single-app, alerting
  responsibility, fingerstick fallback). Rewording for clarity is welcome;
  dropping the substance is not.
- User-facing text is for people managing their own or a family member's
  diabetes. Use plain language, define jargon on first use, and never give
  individualized dosing advice.

## Practical notes

- `swift test` runs the core suite; keep it green and add tests for protocol
  changes with real wire fixtures.
- `G6SensorCore` must not import LoopKit, LoopKitUI, or HealthKit. Host and
  LoopKit-fork differences belong in `Common/` shims.
- Regenerate the Xcode project with `ruby Scripts/generate_project.rb` after
  adding or moving sources, and commit the result.
- Vendored code must come from MIT-licensed sources with its original copyright
  header kept. Do not copy code from GPL-licensed projects such as xDrip4iOS —
  protocol facts may be re-implemented, concrete code may not.
- No secrets in the repository. Credentials belong in the Keychain at runtime.
- Never include real CGM traces, device logs, names, emails, or other
  identifiers in code, comments, commits, issues, or documentation.
  De-identify anything used for debugging.
- Validate BLE changes on real hardware with `Apps/G6SensorHarness` before
  proposing them; note in the PR what you tested and for how long.
