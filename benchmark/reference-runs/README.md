# Reference runs

`tool-0.1.0.tar.gz` holds the eight 0.1.0 tool-programme runs (GitHub Actions runs 39930259189 to 39930286282, 216 sessions) as their artifacts left them: `results.json`, `results.csv`, `summary.json` and the saved `responses/`.

To rebuild the labels in `docs/label/`:

```powershell
tar -xzf benchmark/reference-runs/tool-0.1.0.tar.gz -C $env:TEMP
pwsh benchmark/Get-HyperdotLabel.ps1 -Results $env:TEMP/runs -Coverage coverage.json -Version 0.1.0 -OutDir docs/label
```

The coverage report is `tests/Get-KitCoverage.ps1`'s output of the self-test run on the tagged commit.
