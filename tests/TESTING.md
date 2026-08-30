# Testing

Wait State uses a seven-layer fail-closed test model.

| Layer | Evidence |
| --- | --- |
| Git hook | `.githooks/pre-push` runs local tests and gates |
| Static | ShellCheck plus C28-C43 vendored gates |
| Unit | Node tests for PSI parsing, history, copy, and thresholds |
| Integration | QML/manifest/service contract and accessibility tests |
| System | `rig-verify.sh` runs the real Omarchy validator and `qmllint` on Buzz |
| E2E | `e2e/buzz.sh` starts an isolated real shell, exercises the production reader and state parser, opens the panel, and captures it |
| Acceptance | C43 requires exact copy, a themed banner, a hash-bound render receipt, and explicit visual approval |

The default suite enforces 95% statements, lines, and functions plus 90%
branches. Mutation testing blocks below 90%. `test:race` repeats the complete
offline suite three times with concurrent test execution. The Buzz fixture is
rig-only: production contains no fixture switch and reads the same fixed procfs
paths and persisted state format used by a real desktop.
