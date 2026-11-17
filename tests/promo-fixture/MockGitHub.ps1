#!/usr/bin/env pwsh
# A stand-in for the GitHub REST API and GitHub Models, for Test-Promo.ps1. Answers from -Routes, a JSON object read again on
# every request so the test can change it between runs: "METHOD /path" (no query) -> { "status": 200, "body": ... }. A path
# with no route answers as GitHub would for a commit with nothing on it: no check runs, no pull requests; anything else is 404.
# Every request is appended to -Log as one JSON line (method, path, query, body), in the order it arrived.
param([Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$Routes, [Parameter(Mandatory)][string]$Log)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $reader = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8)
    $body = $reader.ReadToEnd()
    $path = $request.Url.AbsolutePath
    $entry = [ordered]@{ method = $request.HttpMethod; path = $path; query = $request.Url.Query; body = $body } | ConvertTo-Json -Compress -Depth 3
    Add-Content -LiteralPath $Log -Value $entry -Encoding utf8
    $table = Get-Content -LiteralPath $Routes -Raw | ConvertFrom-Json -AsHashtable -Depth 20
    $key = "$($request.HttpMethod) $path"
    $status = 404; $answer = [ordered]@{ message = 'Not Found' }
    if ($path -eq '/__stop') { $status = 200; $answer = 'bye' }
    elseif ($table.ContainsKey($key)) { $status = [int]$table[$key]['status']; $answer = $table[$key]['body'] }
    elseif ($request.HttpMethod -eq 'GET' -and $path -match '/check-runs$') { $status = 200; $answer = [ordered]@{ total_count = 0; check_runs = @() } }
    elseif ($request.HttpMethod -eq 'GET' -and $path -match '/commits/[0-9a-f]+/pulls$') { $status = 200; $answer = @() }
    # As GitHub does, check_name narrows the runs to that name: a wrong name finds none.
    $wanted = $request.QueryString['check_name']
    if ($wanted -and $answer -is [System.Collections.IDictionary] -and $answer.Contains('check_runs')) {
        $runs = @($answer['check_runs'] | Where-Object { $_['name'] -eq $wanted })
        $answer = [ordered]@{ total_count = $runs.Count; check_runs = $runs }
    }
    $text = ConvertTo-Json -InputObject $answer -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $context.Response.StatusCode = $status
    $context.Response.ContentType = 'application/json; charset=utf-8'
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.Close()
    if ($path -eq '/__stop') { $listener.Stop() }
}
