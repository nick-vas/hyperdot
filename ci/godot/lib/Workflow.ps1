# Which kit command to run now: ci/godot/workflow.json holds the rules, status reports the result as suggestedCommands.
# docs/workflow.md is the same table for people. Nothing here runs a command or writes a file.

function Read-WorkflowTable {
    return Get-Content -LiteralPath (Join-Path $PSScriptRoot '../workflow.json') -Raw | ConvertFrom-Json -Depth 8
}

# The stage (0 concept to 6 post-launch) of a plan phase id, or $null for a phase the table does not know (a plan edited by hand).
function Get-WorkflowStage($Table, [string]$PhaseId) {
    if (-not $PhaseId -or -not $Table.stages.PSObject.Properties[$PhaseId]) { return $null }
    return [int]$Table.stages.$PhaseId
}

# $Runs: command -> its newest history entry (Get-LastRuns). $Files: FileInfo list of the project. $Now is a parameter for the test.
function Get-SuggestedCommands($Table, $Runs, [object[]]$Files, $Stage, [datetime]$Now = (Get-Date)) {
    $found = [ordered]@{}
    foreach ($rule in $Table.rules) {
        if ($found.Contains($rule.command)) { continue }
        $from = $rule.PSObject.Properties['fromStage'] ? [int]$rule.fromStage : $null
        if ($null -ne $from -and ($null -eq $Stage -or $Stage -lt $from)) { continue }
        $last = $Runs.Contains($rule.command) ? $Runs[$rule.command] : $null
        $patterns = @($rule.PSObject.Properties['files'] ? $rule.files : @())
        $matching = @(if ($patterns.Count) { $Files | Where-Object { $name = $_.Name; @($patterns | Where-Object { $name -like $_ }).Count -gt 0 } })
        $fire = switch ($rule.trigger) {
            'never-run' { -not $last -and ($patterns.Count -eq 0 -or $matching.Count -gt 0) }
            'failed-last' { $last -and -not $last.ok }
            'files-newer' {
                $newest = $matching | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
                $last -and $newest -and $newest.LastWriteTimeUtc -gt (ConvertTo-UtcTime $last.time)
            }
            'older-than' { $last -and ($Now.ToUniversalTime() - (ConvertTo-UtcTime $last.time)).TotalDays -gt [double]$rule.days }
            default { $false }
        }
        if ($fire) {
            $found[$rule.command] = [ordered]@{ command = $rule.command; args = ($rule.PSObject.Properties['args'] ? [string]$rule.args : '')
                reason = [string]$rule.reason; rule = [string]$rule.id }
        }
    }
    return @($found.Values)
}
