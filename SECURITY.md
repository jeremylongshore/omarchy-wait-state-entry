# Security

## Reporting

Report a vulnerability privately through this repository's **Security** tab,
using *Report a vulnerability*. Please do not open a public issue first.

Expect an acknowledgement within a few days. This is a personal project, not a
staffed product, and that is stated plainly rather than promised around.

## What this plugin is, in security terms

It is QML running **unsandboxed inside a long-lived Quickshell process** on your
desktop, with whatever access your user has. That is true of every Omarchy
plugin, and it is why the rules below are treated as invariants rather than
preferences.

## Invariants

Wait State reads only `/proc/pressure/cpu`, `/proc/pressure/memory`, and
`/proc/pressure/io`. It makes no network requests, accepts no user-provided
paths, handles no credentials, and performs no privileged or destructive
action.

- **No secret in a process argument.** `/proc/<pid>/cmdline` is world-readable,
  so any credential reaches its subprocess through stdin. An environment
  variable is better than an argument, because `/proc/<pid>/environ` is
  owner-only, but stdin is the standard used here.
- **Untrusted text cannot render markup or escape its row.** Anything from a
  network response or another program is `Text.PlainText`, width-bound, and
  elided.
- **Bounded input.** Any read whose size is controlled elsewhere is capped by
  count and by bytes, at the reader and again at the parser, because this
  process never restarts. When a bound truncates, the panel says so.
- **No shell built from data.** Subprocesses take an argv array. Where a shell
  is unavoidable, values are quoted.
- **No network.** The plugin has no remote data source or outbound request.
- **State is disposable.** Everything under `~/.local/state/omarchy/` for this
  plugin can be deleted at any time and is rebuilt on the next poll.

## What is not claimed

Passing the gate lane, `omarchy-plugin-validate`, or `qmllint` is not a security
audit. Those are static checks; two of them skip entirely when their binaries
are absent. A separate real-shell render is required before release.
