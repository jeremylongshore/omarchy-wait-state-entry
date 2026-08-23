# Wait State Agent Guide

Wait State is an Omarchy service and bar widget that reads Linux pressure stall
information. Runtime code must remain stock-session compatible: QML, JavaScript
loaded by QML, Bash, and coreutils only. Node is permitted only for offline tests.

Before changing runtime code, read `SECURITY.md` and `CONTRIBUTING.md`. Preserve
the fixed procfs inputs, byte bounds, history cap, plain-text rendering, and
truthful unavailable and truncated states.

Required verification:

```bash
npm test
bash scripts/check-lane-freshness.sh
bash scripts/run-plugin-gates.sh .
bash scripts/rig-verify.sh .
bash scripts/rig-render.sh . assets/preview-render.png
```

Static validation is not runtime proof. A release requires a clean real-shell
render and an exact public-URL install on Buzz. Do not hand-edit vendored gates;
use `scripts/sync-gate-lane.sh`.
