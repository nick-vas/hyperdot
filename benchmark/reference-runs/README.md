# Reference runs

`tool-0.1.0.tar.gz` holds the eight 0.1.0 tool-programme runs (GitHub Actions runs 39930259189 to 39930286282, 8 results of 24 sessions each, 192 sessions and 240 calls) as their artifacts left them: `results.json`, `results.csv`, `summary.json` and the saved `responses/`.

`coverage.json` is the coverage report the labels were rated with: the percentages of `tests/Get-KitCoverage.ps1`'s output (functions, error codes, commands) from the self-test run on the tagged commit.

To rebuild the labels in `docs/label/` byte for byte (`tests/Test-HyperdotLabel.ps1` does this and compares):

```powershell
tar -xzf benchmark/reference-runs/tool-0.1.0.tar.gz -C $env:TEMP
pwsh benchmark/Get-HyperdotLabel.ps1 -Results $env:TEMP/runs -Coverage benchmark/reference-runs/coverage.json -Version 0.1.0 -OutDir docs/label -Note 'adversarial review: 62 findings, 59 fixed with regression tests'
```
