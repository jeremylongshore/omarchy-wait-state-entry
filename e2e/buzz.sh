#!/usr/bin/env bash
# Acceptance lane: static rig checks plus populated live service, panel, and
# visual evidence on the production Buzz Omarchy container.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/rig-verify.sh" "$ROOT"
"$ROOT/scripts/rig-render.sh" "$ROOT" "$ROOT/preview.png"
test -s "$ROOT/preview.png"
jq -e '.sourceDirty == false and .sourcePackageSha256 == .remotePackageSha256
  and .omarchyPluginValidate == 0 and .qmllintErrors == 0' \
  "$ROOT/.rig-proof.json" >/dev/null
jq -e '.sourceDirty == false and .sourcePackageSha256 == .remotePackageSha256
  and (.previewSha256 | length == 64) and .dimensions == "1280 x 720"
  and .nonblackCoverage >= 0.35 and (.runId | length > 0)
  and (.rawShellLogSha256 | length == 64)
  and .storyEvidence.resourceCount == 3 and .storyEvidence.historySamples == 49
  and .storyEvidence.currentResource == "cpu" and .storyEvidence.currentPressure == 24.8
  and .storyEvidence.severity == "critical"
  and .storyEvidence.allPrimaryRowsExpected == true and .outputScale == 1.25
  and .visualInspection.status == "pending"
  and .primaryAction == "live IPC opened the populated pressure panel"' \
  "$ROOT/.render-proof.json" >/dev/null
