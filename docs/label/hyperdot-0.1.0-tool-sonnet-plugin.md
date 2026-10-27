# Product information sheet: Hyperdot 0.1.0, tool efficiency, claude-sonnet-5-5 with the plugin

![label](hyperdot-0.1.0-tool-sonnet-plugin.svg)

| | |
|---|---|
| Supplier, product, version | nick-vas, Hyperdot, 0.1.0 |
| Model, plugin | claude-sonnet-5-5, loaded |
| Scale | 2026-10 ([method](../label.md)) |
| Standard programme | A-baseline, 8 tasks of `benchmark/token-benchmark.json` (sha256 f521ee805d02), 24 sessions |
| Tool efficiency class | **F** |
| Agent Efficiency Index | 100.4 |
| Tokens per solved task | 85,563 |
| Answers that pass | 62.5% |
| Cost per solved task | $0.0633 (Claude Code's figure) |
| Median session time | 10 s |
| Coverage class | **A** (index 97.2: functions 93.5%, error codes 98.2%, commands 100%) |
| Runs | 20261023-091344 (2.1.309 (Claude Code)) |
| Note | adversarial review: 62 findings, 59 fixed with regression tests |

| Task | Tokens per solved task | Standard |
|---|---:|---:|
| COMP-PS-001 | 626,380 | 256,000 |
| COMP-GD-001 | 73,703 | 73,000 |
| CODE-PS-001 | 40,347 | 48,000 |
| CODE-PS-002 | 63,966 | 86,000 |
| DEBUG-PS-001 | 446,790 | 116,000 |
| DEBUG-GD-001 | 23,626 | 93,000 |
| CI-PS-001 | 35,232 | 56,000 |
| CI-PS-003 | 71,466 | 66,000 |
