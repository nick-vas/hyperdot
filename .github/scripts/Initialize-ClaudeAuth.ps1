#!/usr/bin/env pwsh
# How the Evals and Token benchmark workflows sign Claude Code in, chosen by their `auth` input:
#   subscription  the repository secret CLAUDE_CODE_OAUTH_TOKEN (claude setup-token); runs count against the plan's usage
#   api-key       the repository secret ANTHROPIC_API_KEY (an Anthropic Console key); runs are billed to the API account
# The workflow hands the chosen secret over as CLAUDE_CODE_OAUTH_TOKEN or HYPERDOT_API_KEY (the other one empty). For
# api-key this script exports ANTHROPIC_API_KEY to the later steps (GITHUB_ENV; Actions keeps masking it), because Claude
# Code takes it over a token. Then one small request: a credential that is missing, malformed or refused fails here, by
# name, instead of as a run of 0 scores. -What names what the credential is for, in the messages.
param(
    [ValidateSet('subscription', 'api-key')][string]$Auth = 'subscription',
    [string]$What = 'run this workflow',
    # Make no request (the self-test checks the messages and the export without calling the model).
    [switch]$NoProbe
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ($Auth -eq 'api-key') {
    $key = "$env:HYPERDOT_API_KEY"
    if (-not $key) { throw "Add the repository secret ANTHROPIC_API_KEY (an Anthropic Console API key, ideally in a workspace with a spend limit) to $What with auth: api-key" }
    # A line break would let the secret write other variables into GITHUB_ENV.
    if ($key -match '[\r\n]') { throw 'ANTHROPIC_API_KEY contains a line break; paste it again as one line' }
    if ($key -match '\s') { Write-Host '::warning::ANTHROPIC_API_KEY contains spaces; paste it again as one line' }
    if ($key -notmatch '^sk-ant-api') { Write-Host '::warning::ANTHROPIC_API_KEY does not start like a Console API key (sk-ant-api...)' }
    if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "ANTHROPIC_API_KEY=$key" }
    $env:ANTHROPIC_API_KEY = $key
    $name = 'ANTHROPIC_API_KEY'
    $fix = 'create a key in the Anthropic Console and replace the secret'
} else {
    $token = "$env:CLAUDE_CODE_OAUTH_TOKEN"
    if (-not $token) { throw "Add the repository secret CLAUDE_CODE_OAUTH_TOKEN (from claude setup-token) to $What, or run with auth: api-key and the secret ANTHROPIC_API_KEY" }
    if ($token -match '\s') { Write-Host '::warning::CLAUDE_CODE_OAUTH_TOKEN contains spaces or line breaks; paste it again as one line' }
    if ($token -notmatch '^sk-ant-oat') { Write-Host '::warning::CLAUDE_CODE_OAUTH_TOKEN does not start like a claude setup-token token (sk-ant-oat...)' }
    $name = 'CLAUDE_CODE_OAUTH_TOKEN'
    $fix = 'run claude setup-token again and replace the secret'
}
Write-Host "Claude Code signs in with $name ($Auth)"
if ($NoProbe) { exit 0 }
$out = claude -p 'Reply with the single word OK.' --max-turns 1 --output-format json 2>&1
if ($LASTEXITCODE) { throw "Claude Code rejected ${name}; $fix`: $out" }
exit 0
