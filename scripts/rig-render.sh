#!/usr/bin/env bash
# Run Wait State inside an isolated real Omarchy shell, feed deterministic PSI
# values through the unchanged procfs reader, open the real panel, and capture
# the dedicated 16:9 output directly without cropping or post-processing.
set -euo pipefail

TARGET="$(cd "${1:-$(dirname "$0")/..}" && pwd)"
OUT="${2:-$TARGET/preview.png}"
HOST="${OMARCHY_RIG_HOST:-intent-ops-buzz}"
CONTAINER="${OMARCHY_RIG_CONTAINER:-omarchy-rig}"
RES="${OMARCHY_RIG_RESOLUTION:-1280x720}"
SCALE="${OMARCHY_RIG_SCALE:-1.25}"

for tool in jq identify convert; do
  command -v "$tool" >/dev/null 2>&1 || { echo "rig-render: $tool is required" >&2; exit 2; }
done
[[ -f "$TARGET/manifest.json" ]] || { echo "rig-render: no manifest.json" >&2; exit 2; }

MOD="$(jq -r '.id // empty' "$TARGET/manifest.json")"
[[ -n "$MOD" ]] || { echo "rig-render: manifest has no id" >&2; exit 2; }
NAME="${MOD##*.}"
RUN_ID="${NAME}-$$"

fingerprint() {
  ( cd "$TARGET" && find . -type f \
      -not -path './.git/*' -not -path './tests/*' -not -path './scripts/*' \
      -not -path './node_modules/*' -not -path './reports/*' -not -path './coverage/*' \
      \( -name '*.qml' -o -name '*.js' -o -name 'manifest.json' -o -perm -u+x \) \
      -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 cat 2>/dev/null \
      | sha256sum | cut -d' ' -f1 )
}

FP="$(fingerprint)"
SOURCE_COMMIT="$(git -C "$TARGET" rev-parse HEAD 2>/dev/null || printf unknown)"
SOURCE_DIRTY=false
if [[ "$SOURCE_COMMIT" == unknown ]] || \
   [[ -n "$(git -C "$TARGET" status --porcelain --untracked-files=all -- \
     '*.qml' '*.js' manifest.json preview.png README.md assets/banner.svg \
     scripts/rig-render.sh 2>/dev/null)" ]]; then
  SOURCE_DIRTY=true
fi

TGZ="$(mktemp -t wait-state-render-XXXXXX.tgz)"
REMOTE="$(mktemp -t wait-state-render-XXXXXX.sh)"
trap 'rm -f "$TGZ" "$REMOTE"' EXIT
tar czf "$TGZ" -C "$TARGET" --exclude=.git --exclude=tests --exclude=scripts \
  --exclude=node_modules --exclude=reports --exclude=coverage \
  --exclude=.rig-proof.json --exclude=.render-proof.json --exclude=preview.png . || {
  echo "rig-render: could not package runtime tree" >&2; exit 2; }
ARCHIVE_SHA="$(sha256sum "$TGZ" | cut -d' ' -f1)"

echo "rig-render: shipping $NAME to $HOST/$CONTAINER"
scp -q -o BatchMode=yes "$TGZ" "$HOST:/tmp/rigrender-$RUN_ID.tgz" || {
  echo "rig-render: cannot reach $HOST" >&2; exit 2; }

cat > "$REMOTE" <<REMOTE_EOF
#!/bin/sh
set -eu
MOD="$MOD"; NAME="$NAME"; RUN_ID="$RUN_ID"; RES="$RES"; SCALE="$SCALE"
RUNTIME=/tmp/wait-state-runtime-\$RUN_ID
RIG_ROOT=/tmp/wait-state-home-\$RUN_ID
STATE_ROOT=/tmp/wait-state-state-\$RUN_ID
RIG_BIN=/tmp/wait-state-bin-\$RUN_ID
SWAY_CONFIG=/tmp/wait-state-sway-\$RUN_ID.conf
SWAY_LOG=/tmp/wait-state-sway-\$RUN_ID.log
QS_LOG=/tmp/wait-state-qs-\$RUN_ID.log
SHOT=/tmp/rigrender-\$RUN_ID.png
PLUGIN_DIR=\$RIG_ROOT/.config/omarchy/plugins/\$NAME
QS_PID=""; SWAY_PID=""
cleanup() {
  [ -z "\$QS_PID" ] || kill "\$QS_PID" 2>/dev/null || true
  [ -z "\$SWAY_PID" ] || kill "\$SWAY_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

for path in "\$RUNTIME" "\$RIG_ROOT" "\$STATE_ROOT" "\$RIG_BIN"; do
  if [ -d "\$path" ]; then find "\$path" -depth -delete; fi
done
mkdir -p "\$RUNTIME" "\$PLUGIN_DIR" "\$STATE_ROOT/omarchy/wait-state" "\$RIG_BIN"
chmod 700 "\$RUNTIME" "\$RIG_ROOT" "\$RIG_ROOT/.config" \
  "\$RIG_ROOT/.config/omarchy" "\$RIG_ROOT/.config/omarchy/plugins" \
  "\$PLUGIN_DIR" "\$STATE_ROOT" "\$STATE_ROOT/omarchy" \
  "\$STATE_ROOT/omarchy/wait-state" "\$RIG_BIN"
tar xzf /tmp/rigrender-\$RUN_ID.tgz -C "\$PLUGIN_DIR"

# Seed only the documented persisted format, using recent relative timestamps.
# Service.qml still loads it through Model.parseState, reads PSI through its
# unchanged Process command, appends the live point, and persists the result.
NOW_MS=\$((\$(date +%s) * 1000))
jq -n --argjson now "\$NOW_MS" '
  {schemaVersion:1,selected:"cpu",history:[range(0;48) as \$i | {
    at:(\$now - ((48 - \$i) * 75000)),
    cpu:(if (\$i % 11) == 0 then 28 else 3 + ((\$i * 3) % 10) end),
    cpuFull:0,
    memory:(1 + ((\$i * 2) % 5)),memoryFull:(0.2 + ((\$i % 3) * 0.2)),
    io:(0.5 + ((\$i * 4) % 6)),ioFull:(0.1 + ((\$i % 2) * 0.1))
  }]}' > "\$STATE_ROOT/omarchy/wait-state/state.json"
chmod 600 "\$STATE_ROOT/omarchy/wait-state/state.json"

# No live host pressure leaks into the marketing image. This private head shim
# preserves the exact argv and line protocol used by the production reader.
cat > "\$RIG_BIN/head" <<'SH'
#!/bin/sh
last=""
for arg in "\$@"; do last="\$arg"; done
case "\$last" in
  */cpu)
    printf '%s\n' 'some avg10=24.80 avg60=12.40 avg300=8.10 total=2400000' \
      'full avg10=0.00 avg60=0.00 avg300=0.00 total=0'
    ;;
  */memory)
    printf '%s\n' 'some avg10=4.20 avg60=3.10 avg300=2.70 total=420000' \
      'full avg10=0.60 avg60=0.40 avg300=0.30 total=60000'
    ;;
  */io)
    printf '%s\n' 'some avg10=1.80 avg60=2.10 avg300=1.40 total=180000' \
      'full avg10=0.20 avg60=0.30 avg300=0.20 total=20000'
    ;;
  *) exec /usr/bin/head "\$@" ;;
esac
SH
chmod 700 "\$RIG_BIN/head"

cat > "\$RIG_ROOT/.config/omarchy/shell.json" <<JSON
{"version":1,"bar":{"position":"top","transparent":false,"centerAnchor":"\$MOD",
"layout":{"left":[{"id":"omarchy.workspaces"}],"center":[],
"right":[{"id":"\$MOD","pollInterval":"30 seconds","barResource":"Worst",
"historyWindow":"1 hour","warningPercent":5,"criticalPercent":20}]}},"plugins":[]}
JSON

cat > "\$SWAY_CONFIG" <<SWAY
output * resolution \$RES scale \$SCALE
seat * hide_cursor 1000
SWAY
export XDG_RUNTIME_DIR="\$RUNTIME"
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  sway --config "\$SWAY_CONFIG" >"\$SWAY_LOG" 2>&1 &
SWAY_PID=\$!
WAYLAND_SOCKET=""; attempt=0
while [ \$attempt -lt 30 ]; do
  WAYLAND_SOCKET=\$(find "\$RUNTIME" -maxdepth 1 -type s -name 'wayland-*' | head -1)
  [ -z "\$WAYLAND_SOCKET" ] || break
  attempt=\$((attempt + 1)); sleep 1
done
[ -n "\$WAYLAND_SOCKET" ] || { echo "rig-render: isolated Wayland socket did not start" >&2; exit 1; }
export WAYLAND_DISPLAY="\${WAYLAND_SOCKET##*/}"
export SWAYSOCK=\$(find "\$RUNTIME" -maxdepth 1 -type s -name 'sway-ipc.*.sock' | head -1)
[ -n "\$SWAYSOCK" ] || { echo "rig-render: isolated Sway IPC did not start" >&2; exit 1; }

export HOME="\$RIG_ROOT" XDG_STATE_HOME="\$STATE_ROOT" OMARCHY_PATH=/root/omarchy
export PATH="\$RIG_BIN:\$PATH"
qs -p /root/omarchy/shell >"\$QS_LOG" 2>&1 &
QS_PID=\$!

attempt=0
while [ \$attempt -lt 30 ]; do
  STATE="\$STATE_ROOT/omarchy/wait-state/state.json"
  if [ -f "\$STATE" ] && jq -e \
    '.selected == "cpu" and (.history | length) == 49 and .history[-1].cpu == 24.8' \
    "\$STATE" >/dev/null 2>&1; then break; fi
  attempt=\$((attempt + 1)); sleep 1
done
[ \$attempt -lt 30 ] || { echo "rig-render: real service did not load history and append PSI" >&2; tail -80 "\$QS_LOG" >&2; exit 1; }
[ -d "/proc/\$QS_PID" ] || { echo "rig-render: Quickshell exited before IPC" >&2; exit 1; }

qs -p /root/omarchy/shell ipc call "\$MOD" toggle >/dev/null 2>&1
sleep 8
[ -d "/proc/\$QS_PID" ] || { echo "rig-render: Quickshell exited after IPC" >&2; exit 1; }

echo "===QML WARNINGS==="
grep -a -iE "(WARN|ERROR).*(qml|scene)|(qml|scene).*(WARN|ERROR)|cannot assign|is not a type|unable to|handler was registered|quickshell has crashed" "\$QS_LOG" \
  | grep -avE "libEGL|MESA|ZINK|failed to get driver|failed to create dri2" | head -20
grim "\$SHOT" 2>/dev/null

echo "===ACTION=== panel-opened"
echo "===RUN=== \$RUN_ID"
echo "===LOGSHA=== \$(sha256sum "\$QS_LOG" | awk '{print \$1}')"
echo "===PACKAGE=== \$(sha256sum /tmp/rigrender-\$RUN_ID.tgz | awk '{print \$1}')"
echo "===SHOT=== \$(ls -l "\$SHOT" | awk '{print \$5}') bytes"
REMOTE_EOF

scp -q -o BatchMode=yes "$REMOTE" "$HOST:/tmp/rigrender-$RUN_ID.sh" || exit 2
set +e
RESULT="$(ssh -o BatchMode=yes "$HOST" "docker cp /tmp/rigrender-$RUN_ID.tgz $CONTAINER:/tmp/ >/dev/null && \
  docker cp /tmp/rigrender-$RUN_ID.sh $CONTAINER:/tmp/ >/dev/null && \
  docker exec $CONTAINER sh /tmp/rigrender-$RUN_ID.sh" 2>&1)"
REMOTE_RC=$?
set -e
if [[ "$REMOTE_RC" -ne 0 ]]; then
  echo "rig-render: remote run failed (exit $REMOTE_RC)" >&2
  printf '%s\n' "$RESULT" >&2
  exit 1
fi

WARNINGS="$(printf '%s' "$RESULT" | sed -n '/===QML WARNINGS===/,/===ACTION===/p' | grep -vE '===' || true)"
SIZE="$(printf '%s' "$RESULT" | grep -oE '===SHOT=== [0-9]+' | grep -oE '[0-9]+' || true)"
REMOTE_SHA="$(printf '%s' "$RESULT" | grep -oE '===PACKAGE=== [a-f0-9]{64}' | awk '{print $2}' || true)"
RAW_LOG_SHA="$(printf '%s' "$RESULT" | grep -oE '===LOGSHA=== [a-f0-9]{64}' | awk '{print $2}' || true)"
REMOTE_RUN_ID="$(printf '%s' "$RESULT" | grep -oE '===RUN=== [a-z0-9-]+' | awk '{print $2}' || true)"
ACTION="$(printf '%s' "$RESULT" | grep -oE '===ACTION=== [a-z0-9-]+' | awk '{print $2}' || true)"

if [[ -n "$WARNINGS" ]]; then
  echo "rig-render: plugin QML warnings:" >&2; printf '%s\n' "$WARNINGS" >&2
fi
if [[ -z "$SIZE" || "$SIZE" -lt 4000 ]]; then
  echo "rig-render: no usable screenshot came back" >&2; printf '%s\n' "$RESULT" >&2; exit 1
fi
[[ "$REMOTE_SHA" == "$ARCHIVE_SHA" ]] || { echo "rig-render: remote package hash mismatch" >&2; exit 1; }
[[ "$RAW_LOG_SHA" =~ ^[a-f0-9]{64}$ && "$REMOTE_RUN_ID" == "$RUN_ID" ]] || {
  echo "rig-render: exact run/log provenance missing" >&2; exit 1; }
[[ "$ACTION" == panel-opened ]] || { echo "rig-render: live panel action proof missing" >&2; exit 1; }

ssh -o BatchMode=yes "$HOST" "docker cp $CONTAINER:/tmp/rigrender-$RUN_ID.png /tmp/rigrender-out-$RUN_ID.png >/dev/null" || exit 1
scp -q -o BatchMode=yes "$HOST:/tmp/rigrender-out-$RUN_ID.png" "$OUT" || exit 1

DIMS="$(identify -format '%wx%h' "$OUT" 2>/dev/null || true)"
COVERAGE="$(convert "$OUT" -colorspace gray -threshold 3% -format '%[fx:mean]' info: 2>/dev/null || true)"
[[ "$DIMS" == 1280x720 ]] || { echo "rig-render: expected 1280x720, found $DIMS" >&2; exit 1; }
if [[ -z "$COVERAGE" ]] || ! awk -v coverage="$COVERAGE" 'BEGIN { exit !(coverage >= 0.35) }'; then
  echo "rig-render: nonblack coverage ${COVERAGE:-unreadable} is below 0.35" >&2; exit 1
fi
if [[ -n "$WARNINGS" ]]; then
  echo "rig-render: refusing receipt for warning-bearing shell log" >&2; exit 1
fi

PREVIEW_SHA="$(sha256sum "$OUT" | cut -d' ' -f1)"
jq -n --arg fp "$FP" --arg commit "$SOURCE_COMMIT" --argjson dirty "$SOURCE_DIRTY" \
  --arg archive "$ARCHIVE_SHA" --arg remote "$REMOTE_SHA" --arg rig "$HOST/$CONTAINER" \
  --arg run "$REMOTE_RUN_ID" --arg logSha "$RAW_LOG_SHA" --arg sha "$PREVIEW_SHA" \
  --arg dimensions "${DIMS/x/ x }" --arg coverage "$COVERAGE" --arg scale "$SCALE" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{fingerprint:$fp,sourceCommit:$commit,sourceDirty:$dirty,
    sourcePackageSha256:$archive,remotePackageSha256:$remote,rig:$rig,runId:$run,rawShellLogSha256:$logSha,
    packageBoundary:"runtime tree only; receipts, tests, developer scripts, reports, and preview excluded",
    evidenceBoundary:"isolated real Omarchy shell and unchanged QML under a dedicated headless compositor; bounded recent history through the production state parser; deterministic PSI through the unchanged fixed procfs reader; live IPC toggle; direct full-frame grim capture with no crop or image post-processing",
    fixture:"rig-only deterministic PSI and bounded recent history; no production fixture branch",
    primaryAction:"live IPC opened the populated pressure panel",
    storyEvidence:{resourceCount:3,historySamples:49,currentResource:"cpu",currentPressure:24.8,severity:"critical",allPrimaryRowsExpected:true},
    outputScale:($scale|tonumber),visualInspection:{status:"pending",previewSha256:$sha,checks:[]},
    previewSha256:$sha,dimensions:$dimensions,nonblackCoverage:($coverage|tonumber),capturedAt:$at}' \
  > "$TARGET/.render-proof.json"

echo "rig-render: wrote $OUT ($DIMS, coverage $COVERAGE)"
echo "rig-render: populated PSI service path and live panel open passed"
