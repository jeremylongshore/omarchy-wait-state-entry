# Requirements traceability

| Requirement | Verification |
| --- | --- |
| Parse only the exact bounded PSI shape | `tests/model.test.js`, `tests/mutation-contract.test.js` |
| Preserve truthful unavailable and truncated states | `tests/model.test.js` |
| Cap history and persistence inputs | `tests/model.test.js` |
| Keep graphical-session runtime free of Node, Python, Ruby, network, and credentials | C31, C35, C38, `tests/contract.test.js` |
| Initialize state privately before loading or writing | `tests/contract.test.js`, Buzz E2E |
| Support pointer and keyboard operation | `tests/a11y.test.js` |
| Use exact 500-character marketplace copy and a themed SVG banner | C43, `tests/contract.test.js` |
| Show the complete value proposition in a real shell screenshot | Buzz E2E, C43, hash-bound visual approval |
