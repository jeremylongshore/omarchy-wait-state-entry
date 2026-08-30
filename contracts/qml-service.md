# Wait State QML service contract

The service owns one fixed module ID and reads only
`/proc/pressure/{cpu,memory,io}` through a 512-byte-per-file command. It must
initialize its state directory with mode 0700 before loading or persisting, and
must pass every reader response through `Model.parseSnapshot` before exposing
it to the bar or panel.

The bar resolves the service through the shell, and the panel consumes only the
service's bounded snapshot, bounded history, validated selection, thresholds,
and status fields. Every `Model` function invoked by QML must remain exported
to the offline Node contract suite. Static QML validation is necessary but not
sufficient; Buzz E2E must prove the service, panel, and IPC open path together.
