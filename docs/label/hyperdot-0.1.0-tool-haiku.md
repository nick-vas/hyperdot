# Product information sheet: Hyperdot 0.1.0, tool efficiency, claude-haiku-5-5

![label](hyperdot-0.1.0-tool-haiku.svg)

| | |
|---|---|
| Supplier, product, version | nick-vas, Hyperdot, 0.1.0 |
| Model, plugin | claude-haiku-5-5, not loaded |
| Scale | 2026-10 ([method](../label.md)) |
| Standard programme | A-baseline, 8 tasks of `benchmark/token-benchmark.json` (sha256 f521ee805d02), 24 sessions |
| Tool efficiency class | **D** |
| Agent Efficiency Index | 74.2 |
| Tokens per solved task | 86,041 |
| Answers that pass | 95.8% |
| Cost per solved task | $0.0042 (Claude Code's figure) |
| Median session time | 11.4 s |
| Coverage class | **A** (index 97.2: functions 93.5%, error codes 98.2%, commands 100%) |
| Runs | 20261023-091335 (2.1.309 (Claude Code)) |
| Note | adversarial review: 62 findings, 59 fixed with regression tests |

| Task | Tokens per solved task | Standard |
|---|---:|---:|
| COMP-PS-001 | 216,101 | 256,000 |
| COMP-GD-001 | 72,582 | 73,000 |
| CODE-PS-001 | 45,343 | 48,000 |
| CODE-PS-002 | 159,143 | 86,000 |
| DEBUG-PS-001 | 78,466 | 116,000 |
| DEBUG-GD-001 | 66,413 | 93,000 |
| CI-PS-001 | 21,376 | 56,000 |
| CI-PS-003 | 22,359 | 66,000 |

Other profiles (informative, not rated):

| Profile | AEI | Pass | Tokens per solved task | Cost per solved task |
|---|---:|---:|---:|---:|
| B-scoped | 94.5 | 87.5% | 82,355 | $0.0062 |
| C-iterative | 120.1 | 100% | 106,040 | $0.0084 |
