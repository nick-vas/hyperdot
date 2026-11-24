#!/usr/bin/env pwsh
# Self-test of .github/scripts/Initialize-ClaudeAuth.ps1, the sign-in step of the Evals and Token benchmark workflows: each
# auth names its missing secret, api-key exports ANTHROPIC_API_KEY to GITHUB_ENV and refuses a key with a line break (it
# would write other variables there), subscription exports nothing, and a credential the CLI refuses fails by name. A
# stand-in `claude` answers the one request, so no model is called. The workflows hand over only the chosen secret, and
# every job that does signs in through the script.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script = Join-Path $root '.github/scripts/Initialize-ClaudeAuth.ps1'
$failures = @()
function Assert-True([bool]$Condition, [string]$Name) {
    if ($Condition) { Write-Host "ok     $Name" } else { Write-Host "FAIL   $Name"; $script:failures += $Name }
}
$work = Join-Path ([System.IO.Path]::GetTempPath()) "claude-auth-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
New-Item -ItemType Directory -Force $work | Out-Null
$saved = @{}
foreach ($name in 'HYPERDOT_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY', 'GITHUB_ENV', 'PATH', 'FAKE_CLAUDE_EXIT', 'EXPECT_KEY') { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
# Runs the script in a child pwsh with these variables; returns its exit code, output and what it added to GITHUB_ENV.
function Invoke-Auth([string[]]$Arguments, [hashtable]$Env) {
    $githubEnv = Join-Path $work "github-env-$([guid]::NewGuid().ToString('n').Substring(0, 6))"
    New-Item -ItemType File $githubEnv | Out-Null
    foreach ($name in 'HYPERDOT_API_KEY', 'CLAUDE_CODE_OAUTH_TOKEN', 'ANTHROPIC_API_KEY', 'FAKE_CLAUDE_EXIT', 'EXPECT_KEY') { [Environment]::SetEnvironmentVariable($name, $null) }
    $env:GITHUB_ENV = $githubEnv
    foreach ($name in $Env.Keys) { [Environment]::SetEnvironmentVariable($name, $Env[$name]) }
    $out = & pwsh -NoProfile -NonInteractive -File $script @Arguments 2>&1 | Out-String
    return @{ code = $LASTEXITCODE; out = $out; env = (Get-Content -LiteralPath $githubEnv -Raw) }
}
try {
    $r = Invoke-Auth @('-Auth', 'subscription', '-What', 'run evals', '-NoProbe') @{}
    Assert-True ($r.code -ne 0 -and $r.out -match 'Add the repository secret CLAUDE_CODE_OAUTH_TOKEN' -and $r.out -match 'to run evals' -and $r.out -match 'auth: api-key') "subscription without the token names it, and the api-key route: $($r.out.Trim() -split "`n" | Select-Object -First 1)"
    $r = Invoke-Auth @('-Auth', 'subscription', '-NoProbe') @{ CLAUDE_CODE_OAUTH_TOKEN = 'sk-ant-oat01-stand-in' }
    Assert-True ($r.code -eq 0 -and -not $r.env -and $r.out -match 'signs in with CLAUDE_CODE_OAUTH_TOKEN') 'subscription with a token exports nothing'
    $r = Invoke-Auth @('-Auth', 'api-key', '-What', 'run the benchmark', '-NoProbe') @{ CLAUDE_CODE_OAUTH_TOKEN = 'sk-ant-oat01-stand-in' }
    Assert-True ($r.code -ne 0 -and $r.out -match 'Add the repository secret ANTHROPIC_API_KEY' -and $r.out -match 'spend limit' -and $r.out -match 'to run the benchmark') 'api-key without the key names it, even with a token present'
    $r = Invoke-Auth @('-Auth', 'api-key', '-NoProbe') @{ HYPERDOT_API_KEY = "sk-ant-api03-stand-in`nOTHER=1" }
    Assert-True ($r.code -ne 0 -and $r.out -match 'line break' -and -not $r.env) 'a key with a line break is refused before anything reaches GITHUB_ENV'
    $r = Invoke-Auth @('-Auth', 'api-key', '-NoProbe') @{ HYPERDOT_API_KEY = 'sk-ant-api03-stand-in' }
    Assert-True ($r.code -eq 0 -and $r.env.Trim() -eq 'ANTHROPIC_API_KEY=sk-ant-api03-stand-in') "api-key exports ANTHROPIC_API_KEY to the later steps: $($r.env)"
    $r = Invoke-Auth @('-Auth', 'api-key', '-NoProbe') @{ HYPERDOT_API_KEY = 'not-a-console-key' }
    Assert-True ($r.code -eq 0 -and $r.out -match 'does not start like a Console API key') 'a key of another shape is a warning, not a stop'

    # The one request, against a stand-in CLI that sees which credential it was given.
    if (-not $IsWindows) {
        $bin = Join-Path $work 'bin'
        New-Item -ItemType Directory -Force $bin | Out-Null
        # It refuses unless it was given the key EXPECT_KEY names, so a pass proves the key reached it.
        Set-Content -LiteralPath (Join-Path $bin 'claude') -Value "#!/bin/sh`nif [ -n ""`$EXPECT_KEY"" ] && [ ""`$ANTHROPIC_API_KEY"" != ""`$EXPECT_KEY"" ]; then echo 'wrong key'; exit 3; fi`nexit `${FAKE_CLAUDE_EXIT:-0}`n"
        & chmod +x (Join-Path $bin 'claude')
        $path = "$bin$([IO.Path]::PathSeparator)$($saved['PATH'])"
        $r = Invoke-Auth @('-Auth', 'api-key') @{ HYPERDOT_API_KEY = 'sk-ant-api03-stand-in'; PATH = $path; EXPECT_KEY = 'sk-ant-api03-stand-in' }
        Assert-True ($r.code -eq 0) "the request runs, and the CLI is given the key: $(($r.out.Trim() -split "`n")[-1])"
        $r = Invoke-Auth @('-Auth', 'api-key') @{ HYPERDOT_API_KEY = 'sk-ant-api03-stand-in'; PATH = $path; EXPECT_KEY = 'another-key' }
        Assert-True ($r.code -ne 0 -and $r.out -match 'wrong key') 'and the stand-in tells keys apart, so that pass means something'
        $r = Invoke-Auth @('-Auth', 'api-key') @{ HYPERDOT_API_KEY = 'sk-ant-api03-stand-in'; PATH = $path; FAKE_CLAUDE_EXIT = '1' }
        Assert-True ($r.code -ne 0 -and $r.out -match 'Claude Code rejected ANTHROPIC_API_KEY' -and $r.out -match 'Anthropic Console') 'a refused key fails by name, with what to do'
        $r = Invoke-Auth @('-Auth', 'subscription') @{ CLAUDE_CODE_OAUTH_TOKEN = 'sk-ant-oat01-stand-in'; PATH = $path; FAKE_CLAUDE_EXIT = '1' }
        Assert-True ($r.code -ne 0 -and $r.out -match 'Claude Code rejected CLAUDE_CODE_OAUTH_TOKEN' -and $r.out -match 'claude setup-token') 'a refused token fails by name, with what to do'
    }

    # The workflows: only the chosen secret is handed over, never ANTHROPIC_API_KEY itself, and every job that hands one over signs in through the script.
    foreach ($file in 'evals.yml', 'token-benchmark.yml') {
        $text = Get-Content -LiteralPath (Join-Path $root ".github/workflows/$file") -Raw
        $tokenLines = @([regex]::Matches($text, '(?m)^\s*CLAUDE_CODE_OAUTH_TOKEN:.*$') | ForEach-Object Value)
        $keyLines = @([regex]::Matches($text, '(?m)^\s*HYPERDOT_API_KEY:.*$') | ForEach-Object Value)
        $calls = [regex]::Matches($text, 'Initialize-ClaudeAuth\.ps1 -Auth').Count
        Assert-True ($tokenLines.Count -gt 0 -and @($tokenLines | Where-Object { $_ -notmatch "inputs\.auth != 'api-key' && secrets\.CLAUDE_CODE_OAUTH_TOKEN" }).Count -eq 0) "${file}: the token is handed over only for subscription"
        Assert-True ($keyLines.Count -eq $tokenLines.Count -and @($keyLines | Where-Object { $_ -notmatch "inputs\.auth == 'api-key' && secrets\.ANTHROPIC_API_KEY" }).Count -eq 0) "${file}: the key only for api-key, in every job that has the token"
        Assert-True ($text -notmatch '(?m)^\s*ANTHROPIC_API_KEY:' -and $calls -eq $tokenLines.Count -and $text -match "options: \[subscription, api-key\]") "${file}: ANTHROPIC_API_KEY is never set directly, and each such job signs in through the script ($calls)"
    }
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "`n$($failures.Count) failed"; exit 1 }
Write-Host "`nClaude sign-in self-test passed"
exit 0
