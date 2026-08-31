# Marketplace contract

Wait State ships one bar widget and one service whose listing copy and runtime
behavior tell the same product story.

- Root and bar-widget descriptions are identical and exactly 500 characters.
- Copy distinguishes Linux pressure from utilization, names automatic and
  pinned resource selection, states all three history windows and PSI averages,
  qualifies full-stall availability, and discloses bounded local history.
- `assets/banner.svg` identifies Wait State and depicts pressure telemetry.
- `preview.png` is accepted only with current-tree Buzz provenance, exact
  1280x720 dimensions, a clean shell-log hash, and visual approval.
- The service reads only three fixed procfs files, writes bounded plugin state,
  and has no network, credentials, telemetry, process-control, or
  system-configuration path.

`tests/contract.test.js`, `contracts/qml-service.md`, and gate C43 enforce the
machine-checkable portions.
