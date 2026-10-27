# Writing PowerShell for Hyperdot

The rules for anyone, person or agent, who writes PowerShell in this repository: the kit (`ci/godot`), the hooks, the
benchmark and the self-tests. Hyperdot needs PowerShell 7.6+ and runs under `Set-StrictMode -Version 3.0` and
`$ErrorActionPreference = 'Stop'`, locally on Windows and on GitHub's Linux runners. [AGENTS.md](../AGENTS.md) ("Working
here") has the short form; this page has every lesson, why it matters and where it comes from.

The 78 lessons merge two reports made on 2026-10-26: 61 from the official PowerShell documentation and 35 from the
PowerShell Community blog, with the 18 that overlap folded together. **Verified** means the behaviour was run in
`pwsh -NoProfile` 7.6.6 on Linux and gave the result described: by those reports, and for the lessons marked
**re-run**, again for this page. Claims about Windows or about versions other than 7.6 come from the sources and were
not run. Each source is a link with a short verbatim quote.

## Read this first

The ten mistakes that cost the most here: each fails silently, or only on the Linux runner.

1. `continue` or `break` inside `ForEach-Object`, `Where-Object`, `.ForEach()` or `.Where()` ends the whole script with
   exit code 0. Use `return` (E1).
2. A native program's non-zero exit code never throws, even under `Stop`. Check `$LASTEXITCODE` on the next line (E2).
3. A `throw` is skipped when a caller passes `-ErrorAction SilentlyContinue` or lowers `$ErrorActionPreference`; the next
   line runs (E3).
4. `Get-Content X | Set-Content X` on Linux truncates the file without an error (20,000 lines became 1,041) (S12).
5. `ConvertTo-Json` without `-Depth` turns level 3 into the text `System.Collections.Hashtable`, and its warning lands on
   stdout of a child `pwsh`, ahead of the JSON (J1, E7).
6. Under strict mode, `.Count` on a scalar or `$null`, and dot access to a missing key or property, throw (S1, S2).
7. Preferences and strict mode do not reach `ForEach-Object -Parallel`, thread jobs, modules or a child `pwsh` (X1).
8. On Linux, a variable passed to a native program is wildcard-expanded when it matches files: quote it (N3).
9. `-f`, `.ToString()`, `[double]::Parse`, `-join` and `Sort-Object` follow the current culture; under `de-DE`,
   `[double]::Parse('1.5')` is 15 (C1).
10. `-Path` reads `[ ]` as a wildcard and returns nothing, without an error, when nothing matches: use `-LiteralPath` (P1).

## Errors and exit codes

### E1. `continue` or `break` in a pipeline block ends the script
- **Rule:** In `ForEach-Object`, `Where-Object`, `.ForEach()`, `.Where()`, or a function body outside any loop, skip an
  item with `return`, never `continue` or `break`.
- **Why:** they look up the call stack for a loop. With none, the runspace ends quietly; with one in a caller, the
  caller's loop moves on. `1..3 | ForEach-Object { if ($_ -eq 2) { continue }; "item $_" }; 'after'` prints `item 1` and
  exits 0. `.ForEach()` does the same (re-run: nothing printed, exit 0). **Verified, re-run.**
- **Source:** [about_Continue](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_continue):
  "Using `continue` inside a pipeline, such as a `ForEach-Object` scriptblock, not only exits the pipeline, it
  potentially terminates the entire runspace." [about_Break](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_break):
  "If it can't find an enclosing construct, the current runspace is quietly terminated."

### E2. A native program's exit code never throws: check `$LASTEXITCODE`
- **Rule:** After every `& tool ...`, test `$LASTEXITCODE` before anything else runs. To have failures throw, set
  `$PSNativeCommandUseErrorActionPreference = $true` inside one function or script block, never globally: calls whose
  failure is expected (`git describe`) would throw.
- **Why:** under `Stop`, `sh -c 'exit 3'` does not throw and `try`/`catch` sees nothing. **Verified, re-run.**
- **Source:** [about_Error_Handling](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_error_handling):
  "By default, a non-zero exit code from a native program: ... Does **not** trigger `catch` or `trap`."
  [about_Preference_Variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_preference_variables):
  "When `$PSNativeCommandUseErrorActionPreference` is `$true`, native commands with non-zero exit codes issue errors
  according to `$ErrorActionPreference`."
- **Since:** 7.4 for the preference, inside the 7.6 floor. The kit's `Invoke-Logged` returns the exit code; keep reading it.

### E3. A lowered preference swallows `throw`; put `return` after a guard `throw`
- **Rule:** Never pass `-ErrorAction SilentlyContinue` or `Ignore` to the kit's own `[CmdletBinding()]` functions, and
  never set `$ErrorActionPreference` below `Stop` around code that can throw (`Stop-GodotCi` throws when
  `$script:CatchStops` is set). To tolerate one expected miss, test first (`Test-Path`) or use `try`/`catch`. After a
  `throw` that fences off dangerous code, add `return`, or use `$PSCmdlet.ThrowTerminatingError()`.
- **Why:** the parameter becomes a scope-local preference, and execution continues on the line after the `throw`.
  `function F { [CmdletBinding()] param() throw 'boom'; 'F-after-throw' }; F -ErrorAction SilentlyContinue` prints
  `F-after-throw`. `hyperdot.ps1`'s top-level `trap` catches it; tools, tests and benchmark scripts have no such trap.
  **Verified, re-run.**
- **Source:** [about_Error_Handling](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_error_handling):
  "When calling an advanced function with `-ErrorAction SilentlyContinue`, the parameter translates to a scope-local
  `$ErrorActionPreference` value, so it also suppresses `throw` inside that function."
  [On Preferences and Scopes](https://devblogs.microsoft.com/powershell-community/how-to-have-more-control-of-preferences-in-functions-and-the-role-of-modules-on-inheritance/):
  "When it is acting as a 'fence' around dangerous code, it is worth putting a `return` after `throw`."

### E4. `Stop` set inside an advanced function stops only the statement
- **Rule:** Set `$ErrorActionPreference = 'Stop'` once at the top of each entry script and test script, and let child
  scopes inherit it; do not count on setting it inside an advanced function to stop the run.
- **Why:** `& { [CmdletBinding()] param() $ErrorActionPreference = 'Stop'; 1/0 } 2>$null; 'after'` prints `after`.
  **Verified.**
- **Source:** [about_Error_Handling](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_error_handling):
  "In **advanced** functions and script blocks (those with `[CmdletBinding()]`), the error remains
  **statement-terminating**. Execution continues at the next statement after the call."

### E5. Catch typed, rethrow bare, wrap with the inner exception
- **Rule:** Catch the narrowest type (an escalated cmdlet error is caught by its own type, such as
  `ItemNotFoundException`). To log and pass on, use a bare `throw`; to change the message, make a new exception with the
  original as `InnerException`; or stop with `Stop-GodotCi`. Copy `$_` to a variable before any pipeline in the `catch`.
  Never turn an exception into `Write-Error` plus `return $null`.
- **Why:** a new exception without the inner one loses the file and line; `$_` is rebound by any nested
  `ForEach-Object`. Under `Stop`, `Write-Error` in a `catch` is itself terminating, so `return $null` never runs; under
  `Continue` the caller carries on with `$null`. **Verified** (the `Write-Error` case).
- **Source:** [Everything about exceptions](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-exceptions):
  "We want to re-throw the exception to preserve the original execution information like source script and line number."
  [Automate Text Summarization with OpenAI](https://devblogs.microsoft.com/powershell-community/automate-text-summarization-with-openai-powershell/)
  (the anti-pattern): `} catch { Write-Error "Failed to invoke OpenAI API: $_"; return $null }`

### E6. Start a child PowerShell as `pwsh -NoProfile -NonInteractive -File`
- **Rule:** Use `-File`; with `-Command`, end the string with `; exit $LASTEXITCODE`. Always pass `-NoProfile` and
  `-NonInteractive`.
- **Why:** under `-Command`, exit codes other than 0 and 1 (124 for a timeout, 2 from the Stop hook) become 1: `exit 7`
  gave 7 through `-File` and 1 through `-Command`. `-NonInteractive` turns a `Mandatory` prompt or `Read-Host` into an
  error instead of a hung job. A profile can change default parameter values, aliases and modules, so without
  `-NoProfile` a developer's run differs from CI. `finally` runs when a function calls `exit`. **Verified.**
- **Source:** [about_Pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh):
  "that exit code is converted to `1` for process exit code." and "Any attempts to use interactive features, like
  `Read-Host` or confirmation prompts, result in statement terminating errors rather than hanging."
  [How to Make Use Of PowerShell Profile Files](https://devblogs.microsoft.com/powershell-community/how-to-make-use-of-powershell-profile-files/):
  "The script is, in effect, dot-sourced".

### E7. In a child `pwsh`, every stream except Error goes to stdout
- **Rule:** In code that can run under `-Json`, log only through `Write-CiLog`/`Write-Console` (stderr in `-Json`). Do
  not call `Write-Host`, `Write-Warning`, `Write-Verbose` or `Write-Information` directly, and keep cmdlets from
  warning on their own (capture with `-WarningAction SilentlyContinue -WarningVariable w`, or `3>$null`, then log).
- **Why:** `pwsh -File streams.ps1 2>/dev/null` printed `WARNING: W`, `H`, `VERBOSE: V`, `I` and `OUT` on stdout;
  only `Write-Error` went to stderr. A stray line ahead of the document breaks `ConvertFrom-Json` for the agent
  reading it, and the contract in [json.md](json.md). **Verified, re-run.**
- **Source:** [Output missing from transcript](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/output-missing-from-transcript):
  "`Write-Host` makes an immediate write to the host process." (Stream routing was run, not quoted.)

### E8. `$LASTEXITCODE` is unset until a native program runs, and stale after
- **Rule:** Read `$LASTEXITCODE` only on the line after the call it belongs to.
- **Why:** under strict mode, reading it before any native program ran throws "The variable '$LASTEXITCODE' cannot be
  retrieved because it has not been set"; cmdlets and functions do not reset it, so a check further down tests another
  program. **Verified.**
- **Source:** [about_Error_Handling](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_error_handling):
  "This variable isn't affected by PowerShell cmdlet errors."

### E9. Dispose streams and handles in `finally`
- **Rule:** `$w = [IO.StreamWriter]::new($path); try { ... } finally { $w.Dispose() }`, and the same for `FileStream`,
  `Process` objects and steppable pipelines (`End()`).
- **Why:** under `Stop`, any error between open and close skips the close; on Windows the open handle locks the file and
  later cleanup of a temporary or results folder fails. Not run (Linux does not lock).
- **Source:** [Measuring average download time](https://devblogs.microsoft.com/powershell-community/measuring-download-time/):
  "finally { # Freeing the unmanaged memory. [System.Runtime.InteropServices.Marshal]::FreeHGlobal($buffer) }"

## Strict mode, arrays and the pipeline

### S1. Count with `@(...)`: `.Count` on a scalar or `$null` throws under strict mode
- **Rule:** `@(<expr>).Count` whenever the value can be empty, one item or a scalar (command output, a function result,
  `Get-Content` of a one-line file, a JSON value).
- **Why:** the docs say every scalar has `Count`; that holds only without strict mode. Under 3.0, `$x = 5; $x.Count`,
  `$null.Count` and `(Get-Item /).Count` throw "The property 'Count' cannot be found". **Verified, re-run.**
- **Source:** [about_Arrays](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arrays):
  "a scalar types and collection of zero or one objects has the **Count** and **Length** properties." (The strict-mode
  exception is not documented.)

### S2. Dot access to a missing key or property throws: index or test first
- **Rule:** For optional data use `$h['key']` or `$h.ContainsKey('key')` (also on `$PSBoundParameters`) and
  `$o.PSObject.Properties['name']` (also on `ConvertFrom-Json` output). Never `$null -ne $obj.Prop` to test existence.
- **Why:** under 3.0, `@{a=1}.missing`, a missing property of a JSON object, `$PSBoundParameters.Value` when not passed,
  and member enumeration on an empty array (`@().Name`) all throw; `$h['missing']` returns `$null`. **Verified.**
- **Source:** [Set-StrictMode](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/set-strictmode):
  "Prohibits references to non-existent properties of an object." The deep dives advise the opposite (see "Advice
  that does not hold here").

### S3. One result is the object itself; indexing one string gives a character
- **Rule:** Wrap with `@()` before indexing or counting; never index a pipeline result.
- **Why:** `$r = @('only.txt') | Where-Object { $_ }; $r[0]` is `o`; `$null[0]` throws. **Verified.**
- **Source:** [about_Arrays](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arrays):
  "if the result is a single object (singleton), and that object has a **Count** or **Length** property, the value of
  those properties belong to the singleton object".

### S4. Functions unroll what they return
- **Rule:** Callers wrap a call in `@()`; when a caller needs the collection itself, return `,$list` or
  `Write-Output -NoEnumerate $list` (a `List[T]` unrolls too).
- **Why:** an empty return becomes `$null` (then S1 throws), one element becomes a scalar.
- **Source:** [about_Return](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_return):
  "PowerShell automatically unrolls the members and passes them one at a time through the pipeline."

### S5. Everything not captured is output: `$null =` the side-effect values
- **Rule:** `$null =` in front of `New-Item`, `ArrayList.Add`, `StringBuilder.Append*`, `HashSet.Add`,
  `Dictionary.TryAdd`, `Process.WaitForExit(ms)` and `-PassThru` calls whose value you do not use.
- **Why:** the values join the function's return value, and a strict caller then fails on `.Prop`.
- **Source:** [about_Return](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_return):
  "the results of each statement are returned as output, even without a statement that contains the `return` keyword."

### S6. `$null` on the left; `-contains` or `-in` for membership
- **Rule:** `$null -eq $x`. Never `if ($list -eq 'x')` to ask "does it contain": use `-contains`, `-in` or
  `.Where({ ... }, 'First')`.
- **Why:** with a collection on the left, `-eq` returns the matching elements and their truthiness decides the `if`;
  with `$v = @($null)`, both `$v -eq $null` and `$v -ne $null` are false. The right side is converted to the left
  side's type (`1 -eq '1.0'` is true).
- **Source:** [about_Comparison_Operators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators):
  "you must put `$null` on the left-hand side of the equality operator."

### S7. A one-item collection is as true as its item; any non-empty string is true
- **Rule:** Test emptiness with `@(...).Count -gt 0`, not `if ($list)`; parse booleans with `[bool]::Parse`.
- **Why:** `[bool]@(0)` is False, `[bool]@(0,0)` True, `[bool]'False'` True. **Verified.**
- **Source:** [about_Booleans](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_booleans):
  "Single-element collections evaluate to the **Boolean** value of their one and only element."

### S8. `$Matches` is overwritten by any later match, also inside `Where-Object`
- **Rule:** Copy captures on the line after the `-match` (`$name = $Matches['name']`), and read them with `['key']`,
  not `.key`.
- **Why:** pipeline blocks run in the caller's scope, so a `$_ -match` in `Where-Object` replaces `$Matches`; and
  `.values`, `.keys` and `.count` fall back to the Hashtable's own members. `ConvertFrom-BenchSweep` in
  `ci/godot/lib/Measure.ps1` prints `' '` instead of the values for this reason. **Verified.**
- **Source:** [about_Comparison_Operators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comparison_operators):
  "When the `-match` result is **False**, ... or when the input is a collection, the `$Matches` automatic variable isn't
  overwritten."

### S9. Copy the keys before changing a dictionary in a loop
- **Rule:** `foreach ($k in @($h.Keys)) { $h[$k] = ... }`.
- **Why:** even setting an existing key inside `foreach ($k in $h.Keys)` throws "Collection was modified". **Verified.**
- **Source:** [Everything about hashtable](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-hashtable):
  "The trick to this situation is to clone the keys before doing the enumeration."

### S10. `switch` loops over arrays, runs every matching clause and skips empty input
- **Rule:** End a clause with `break` when only one should apply; remember `switch (@())` runs nothing, not even
  `default`; matching is case-insensitive and exact unless `-Wildcard`, `-Regex` or `-CaseSensitive`; `continue` in a
  `switch` continues the switch, not the loop around it.
- **Why:** `switch ('abc') { 'a*' {..} 'ABC' {..} {$true} {..} }` ran the last two clauses. **Verified.**
- **Source:** [about_Switch](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_switch):
  "If the value matches multiple conditions, the action for each condition is executed."

### S11. Pin `Set-StrictMode -Version 3.0`, never `Latest`
- **Rule:** Every entry and test script sets `Set-StrictMode -Version 3.0`.
- **Why:** `Latest` can tighten under you on an upgrade; 3.0 is the strictest level there is.
- **Source:** [Set-StrictMode](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/set-strictmode):
  "Using `Latest` for **Version** in scripts isn't deterministic."

### S12. Never read and write one file in one pipeline
- **Rule:** Read the whole file first (`(Get-Content -LiteralPath $f)` in parentheses, or `-Raw`), then write; or write
  to a temporary file and move it into place.
- **Why:** `Get-Content $f | Set-Content $f` on a 20,000-line file left 1,041 lines and no error on Linux;
  `| Add-Content $f` never ends. The blog expects an "in use" error, which may hold on Windows only. **Verified, re-run.**
- **Source:** [Mastering the (steppable) pipeline](https://devblogs.microsoft.com/powershell-community/mastering-the-steppable-pipeline/):
  "`Get-Content` and `Set-Content` are concurrently processing items in the pipeline."

## Strings, culture and encoding

### C1. Format and parse machine-read values with the invariant culture
- **Rule:** For JSON, CSV, file names, logs a test parses and Godot arguments: `.ToString('…', [cultureinfo]::InvariantCulture)`,
  `[string]::Format([cultureinfo]::InvariantCulture, ...)`, `[double]::Parse($s, [cultureinfo]::InvariantCulture)`,
  `[datetime]::ParseExact(..., InvariantCulture)`, dates as `ToString('o')` or `yyyy-MM-dd`. Not `-f`, bare
  `.ToString()`, `-join` of numbers or `Sort-Object`.
- **Why:** under `de-DE`, `'{0:N1}' -f 1.5` is `1,5`, `[double]::Parse('1.5')` is 15, `ToString('yyyy/MM/dd')` gives
  `2021.02.19` (`/` is the culture's separator), and `Get-Date -Date '01/02/2024'` is 1 February while the cast
  `[datetime]'01/02/2024'` is 2 January. Interpolation and casts are invariant. **Verified, re-run.**
- **Source:** [about_Quoting_Rules](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_quoting_rules):
  "PowerShell uses the invariant culture when interpreting expandable string expressions."
  [Getting Yesterday's Date](https://devblogs.microsoft.com/powershell-community/getting-yesterdays-date/): "if you want a
  specific result, using ToString() and a date format string is possibly better" (the culture must be fixed too).

### C2. In strings: `$( )` for members, `${name}` before a colon, no `$` from values in a `-replace` replacement
- **Rule:** `"$($o.Prop)"`, `"${name}:"`. Single-quote a `-replace` replacement; when it holds a value, use
  `$v.Replace('$', '$$')`, `.Replace()` or a script block replacement.
- **Why:** `"$o.Prop"` expands only `$o`; `"$name:"` is a scope-qualified variable; in a double-quoted replacement the
  regex engine reads `$0`, `$1` and `$&` inside the value. **Verified.**
- **Source:** [about_Quoting_Rules](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_quoting_rules):
  "Variables references using array indexing or member access must be enclosed in a subexpression."

### C3. Operators are case-insensitive regex; .NET string methods are case-sensitive and literal
- **Rule:** `-match`, `-replace` and `-split` take regex (escape input with `[regex]::Escape()`); `.Contains()`,
  `.Replace()` and `.StartsWith()` are literal (add a `StringComparison` when case should not matter); `-ceq` and
  `-cmatch` when case matters, such as file names on Linux.
- **Why:** `'a.b' -split '.'` splits on every character; `'SQL Saturday'.Replace('saturday','Sat')` changes nothing.
- **Source:** [about_Case-Sensitivity](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_case-sensitivity):
  ".NET methods often exhibit case-sensitive behavior by default."

### C4. Case-convert identifiers with `ToUpperInvariant()`/`ToLowerInvariant()`
- **Why:** under `tr-TR`, `'file'.ToUpper()` is `FİLE`, and lookups fail. **Verified.**
- **Source:** [Can I Enable the Caps Lock Key?](https://devblogs.microsoft.com/powershell-community/can-i-enable-the-caps-lock-key/)
  (uses `ToUpper()`): "The `ToUpper()` method converts the string to all upper case".

### C5. UTF-8 without BOM; decode native output explicitly; never `-Encoding ASCII` for data
- **Rule:** Leave file encoding at the default (UTF-8, no BOM), `utf8BOM` only for a consumer that needs it, never
  `ascii`. When capturing a native program with `&`, set `[Console]::OutputEncoding` to UTF-8 first, or read through
  `ProcessStartInfo.StandardOutputEncoding` as `Invoke-Logged` does.
- **Why:** `'é' | Out-File f -Encoding ascii` stores `?`; Windows consoles often decode with code page 437 or 850, so
  non-ASCII output of Godot or git comes back wrong. **Verified** (the ASCII case).
- **Source:** [about_Character_Encoding](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_character_encoding):
  "PowerShell (v6 and higher) defaults to `utf8NoBOM` for all text output." [How to send output to a file](https://devblogs.microsoft.com/powershell-community/how-to-send-output-to-a-file/):
  "By default, PowerShell 7 uses the UTF-8 encoding".

### C6. Split lines on `'\r?\n'`; write byte-stable files with `` "`n" `` and `-NoNewline`
- **Rule:** `-split '\r?\n'` for lines (`'\r?\n\s*\r?\n'` for blocks), never `` "`r`n" ``. For files that must be
  identical across systems, join with `` "`n" `` and write with `-NoNewline`.
- **Why:** on Linux, `Out-String` and native output have no CR, so a split on `` "`r`n`r`n" `` found 1 block instead
  of 3. `Set-Content` writes the platform newline (LF on Linux, CRLF on Windows); `Get-Content` strips both, `-Raw`
  keeps them. **Verified.**
- **Source:** [A closer look at the parsing code of a Crescendo output handler](https://devblogs.microsoft.com/powershell-community/a-closer-look-at-the-parsing-code-of-a-crescendo-output-handler/)
  (the anti-pattern): "I split that blob into blocks of text at the blank line using the `` -split "`r`n`r`n" ``
  operator." [Set-Content](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-content):
  "No newline is added after the last output string."

### C7. Do not write files or logs through the formatting system
- **Rule:** Build the text yourself (`-join`, invariant formatting, `ConvertTo-Json`) instead of `Out-File`, `>`,
  `Format-Table` or a bare `Out-String`; if you must, `Out-String -Width <n>`.
- **Why:** `>` renders the console view: tables cut at the window width, collections stop at `$FormatEnumerationLimit`
  (4) items, a local copy of which is ignored; with no console (window width -1) it wrote only blank lines. **Verified.**
- **Source:** [How to send output to a file](https://devblogs.microsoft.com/powershell-community/how-to-send-output-to-a-file/):
  "The `>` operator is equivalent to `Out-File`". [How to Use $FormatEnumerationLimit](https://devblogs.microsoft.com/powershell-community/how-to-use-formatenumerationlimit/):
  "PowerShell seems to only use the globally scoped value, not the locally scoped copy."

### C8. `Set-Content` and `Add-Content` write `ToString()`
- **Rule:** Turn objects into text before writing them.
- **Why:** `@{a=1} | Set-Content f` writes `System.Collections.Hashtable`. **Verified.**
- **Source:** [How to send output to a file](https://devblogs.microsoft.com/powershell-community/how-to-send-output-to-a-file/):
  "these cmdlets use each object's ToString() method to convert the object to a string".

## Native commands

### N1. Pass arguments as an array; never build a command line, never `Invoke-Expression`
- **Rule:** `& $exe @arguments` or `Invoke-Logged $exe @(...)`, one array element per argument.
- **Why:** the array keeps empty strings and embedded quotes intact (7.3+ argument passing, inside the floor);
  `Invoke-Expression` runs whatever the string holds. `.cmd` and `.bat` files still get legacy parsing on Windows.
  **Verified** (`sh -c 'echo $#' x '' b` saw 2 arguments).
- **Source:** [about_Parsing](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parsing):
  "PowerShell 7.3 changed the way the command line is parsed for native commands." [Avoid using Invoke-Expression](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/avoid-using-invoke-expression):
  "The `Invoke-Expression` cmdlet should only be used as a _last resort_."

### N2. `Start-Process -ArgumentList` joins with spaces and adds no quotes
- **Rule:** Do not pass paths or values that may hold spaces through it; use `&` or `ProcessStartInfo.ArgumentList`, or
  quote each element yourself.
- **Why:** `-ArgumentList @('-NoProfile','-File','./count.ps1','one arg with spaces')` reached the script as 4
  arguments; Windows temp paths hold the user name. **Verified.**
- **Source:** [Start-Process](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/start-process):
  "The cmdlet joins the array into a single string with each element of the array separated by a single space."

### N3. On Linux, variables passed to native programs are globbed: quote them
- **Rule:** When a value can hold `*`, `?` or `[` (a filter, a pattern, a user argument), pass `"$value"`, or use
  `ArgumentList`.
- **Why:** with `a.txt` and `v1` in the folder, `$p = 'v[0-9]*'; & /bin/echo --match $p` printed `--match v1`;
  `"$p"` stayed literal. Windows does not glob, so the bug appears only on the runner, and only when a file happens to
  match. **Verified, re-run.**
- **Source:** [Unix support](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support): "Added support
  for native command globbing on Unix platforms." (That variables are expanded too was run, not documented.)

### N4. `2>&1` from a native program gives `ErrorRecord`s, in no fixed order, and is never an error
- **Rule:** Turn merged lines into strings (`| ForEach-Object { "$_" }`), judge success by the exit code, and read both
  streams as `Invoke-Logged` does when order matters.
- **Why:** `sh -c 'echo out; echo err >&2; exit 3' 2>&1` gave the `err` record before `out`, and did not throw under
  `Stop`. Captured error text can carry ANSI colour codes. **Verified.**
- **Source:** [about_Preference_Variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_preference_variables):
  "error records redirected from native commands ... aren't written to the `$Error` variable and the preference variable
  `$ErrorActionPreference` doesn't affect the redirected output."

### N5. Bytes through `>` and `|` between native programs are kept
- **Rule:** Inside the 7.6 floor, piping or redirecting a native program's binary stdout is safe; prefer a tool's own
  output option (`curl -o`) when it has one, for clarity.
- **Why:** before 7.4 the bytes were decoded as text and re-encoded, which corrupted archives.
- **Source:** [about_Redirection](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_redirection):
  "Beginning in PowerShell 7.4, PowerShell preserves the byte-stream data when redirecting the **stdout** stream of a
  native command to a file".

### N6. `&` runs in `$PWD`; `ProcessStartInfo` in the process folder
- **Rule:** Set `$info.WorkingDirectory` whenever you use `ProcessStartInfo` or `Process.Start`.
- **Why:** after `Set-Location sub`, `& pwd` printed `.../sub` and a `ProcessStartInfo('pwd')` the parent.
  `Invoke-Logged` sets none and is safe only because the kit never calls `Set-Location`. **Verified.**
- **Source:** [about_Methods](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_methods):
  ".NET methods use the process working directory. PowerShell cmdlets use the Runspace location."

### N7. Some programs report success with a non-zero exit code
- **Rule:** Compare with the program's own threshold; inside a block that sets
  `$PSNativeCommandUseErrorActionPreference = $true`, turn it off for such a call.
- **Why:** a blanket `-ne 0` fails good runs (the kit already treats Godot's codes from 128 as crashes).
- **Source:** [about_Preference_Variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_preference_variables):
  "Some native commands, like robocopy use non-zero exit codes to represent information other than errors."

### N8. `pwsh -File` passes every argument as one string: no arrays
- **Rule:** Every `[string[]]` parameter of an entry script also accepts one comma-joined string and splits it, as
  `hyperdot.ps1` does for `-Runners`, `-Preset`, `-Scene` and others.
- **Why:** `pwsh -File arr.ps1 -Runners gut,dotnet` gave one element, `gut,dotnet`. **Verified.**
- **Source:** [about_Pwsh](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pwsh):
  "The **File** parameter can't support scripts using a parameter that expects an array of argument values."

### N9. Parse native output by its content, in functions tested on captured output
- **Rule:** Find the header or label with a regex and parse what follows; prefer a machine-readable mode
  (`--porcelain`, `--format json`); keep parsers in their own functions, tested on saved output from both systems; wrap
  native output in `@(...)`.
- **Why:** fixed line offsets differ per OS and version (the netstat example skips 4 lines on Windows and 3 on Linux);
  one line of output is a `String`, two an `Object[]`. **Verified** (the types).
- **Source:** [Converting string output to objects](https://devblogs.microsoft.com/powershell-community/converting-string-output-to-objects/):
  "the table header is on the fourth line (third line for Linux)". [My Crescendo journey](https://devblogs.microsoft.com/powershell-community/my-crescendo-journey/):
  "Writing the output parser is the hardest part of wrapping a native command".

### N10. Do not name a function like a program the kit calls
- **Rule:** No function named `git`, `godot`, `dotnet`, `ffmpeg` or `kill`; where shadowing is possible, call the
  program as `& (Get-Command git -CommandType Application)[0]` and a cmdlet by its module-qualified name.
- **Why:** an alias beats a function, which beats a cmdlet, which beats a program: after `function git { ... }`,
  `git --version` ran the function. **Verified.**
- **Source:** [On Preferences and Scopes](https://devblogs.microsoft.com/powershell-community/how-to-have-more-control-of-preferences-in-functions-and-the-role-of-modules-on-inheritance/):
  "an alias beats a function, which beats a cmdlet, which beats an external program."

## Paths and portability

### P1. `-LiteralPath` for every path from data; `-PathType` when it matters
- **Rule:** Use `-LiteralPath` with `Test-Path`, `Get-Item`, `Get-ChildItem`, `Get-Content`, `Set-Content`, `Copy-Item`,
  `Remove-Item` and `Resolve-Path`; never pipe a string into `Resolve-Path` (it binds to `-Path`); `-Path` only for a
  real wildcard, with literal parts escaped by `[WildcardPattern]::Escape()`. Say `-PathType Leaf` or `Container`.
- **Why:** for an existing `k [v2]/x.gd`, `Test-Path` returned False and `-LiteralPath` True; `(Join-Path ... |
  Resolve-Path).Path` threw "The property 'Path' cannot be found", because `Resolve-Path` returned nothing without an
  error. **Verified, re-run.**
- **Source:** [Test-Path](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/test-path):
  "No characters are interpreted as wildcard characters." [Determine if a folder exists](https://devblogs.microsoft.com/powershell-community/determine-if-a-folder-exists/):
  "`Test-Path` tests the existence of a path and returns a boolean value."

### P2. Files and environment variables are case-sensitive on Linux
- **Rule:** Spell paths, `res://` references and variable names in their exact case (`$env:PATH`, not `$env:Path`);
  compare file names with `-ceq` when the comparison means "the same file on Linux".
- **Why:** a wrong case passes on Windows and fails on the runner. Provider wildcards stay case-insensitive (`-Filter
  *.txt` matched `B.TXT`). **Verified** (the filter).
- **Source:** [about_Case-Sensitivity](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_case-sensitivity):
  "The `FileSystem` and `Environment` providers are case-sensitive on non-Windows systems."

### P3. `Join-Path`, never `[IO.Path]::Combine` or `"$root\sub"`
- **Rule:** Build paths with `Join-Path` or `[IO.Path]::Join`; normalise to `/` before comparing or emitting; join
  PATH-like lists with `[IO.Path]::PathSeparator`.
- **Why:** `[IO.Path]::Combine('a','/b')` is `/b`; cmdlets accept `\` on Linux but `[IO.File]::Exists("$d\f.txt")` is
  False; `[IO.Path]::GetFileName('dir\file.txt')` returns the whole string on Linux. **Verified.**
- **Source:** [Unix support](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support): "Paths given to
  cmdlets are now slash-agnostic". [Creating a scalable, customised running environment](https://devblogs.microsoft.com/powershell-community/creating-a-scalable-customised-running-environment/):
  "`-join [System.IO.Path]::PathSeparator`".

### P4. Give .NET absolute paths only
- **Rule:** `[IO.File]`, `[IO.Directory]`, `GetFullPath`, `StreamWriter`, `XmlDocument.Save` and the like get paths
  built from `$PSScriptRoot`, the project folder or another absolute root; resolve others with
  `$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($p)`.
- **Why:** after `Set-Location sub`, `Test-Path f.txt` was True and `[IO.File]::Exists('f.txt')` False, and
  `WriteAllText('rel.txt', ...)` wrote into the folder pwsh started in. **Verified.**
- **Source:** [Set-Location](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/set-location):
  "This is not the same as `[System.Environment]::CurrentDirectory`." [Update XML files using PowerShell](https://devblogs.microsoft.com/powershell-community/update-xml-files-using-powershell/)
  (the anti-pattern): `$xml.Save($path)`.

### P5. No aliases in scripts
- **Rule:** Full cmdlet names (`Get-ChildItem`, `Sort-Object`, `Start-Sleep`, ...); a native program whose name is a
  Windows alias (`kill`, `ps`) is called as `& kill`, behind an OS check.
- **Why:** `ls`, `cat`, `cp`, `mv`, `rm`, `ps`, `sort`, `sleep`, `diff`, `tee`, `kill` and `start` are cmdlets on
  Windows and programs on Linux, which return text; PSScriptAnalyzer on Linux cannot see it, since there they are not
  aliases.
- **Source:** [Unix support](https://learn.microsoft.com/powershell/scripting/whats-new/unix-support): "the
  "convenience aliases" for the basic commands `ls`, `cp`, `mv`, `rm`, `cat`, `man`, `mount`, and `ps` were removed".

### P6. `Copy-Item -Recurse` into an existing folder nests the source
- **Rule:** Copy `"$src/*"`, or remove or create the destination first.
- **Why:** the first copy made `dst/f`, the second `dst/src/f`; a re-run sees another tree. **Verified.**
- **Source:** [Copy-Item](https://learn.microsoft.com/powershell/module/microsoft.powershell.management/copy-item):
  "If the path `C:\Drawings` doesn't exist the cmdlet copies all the files from the `Logfiles` folder tree into a single
  folder".

### P7. Sort ordinally when order reaches output
- **Rule:** For JSON, CSV, reports and snapshots, sort with `[Array]::Sort($a, [StringComparer]::Ordinal)` or
  `Sort-Object -Stable` on a key that is never equal; never rely on enumeration order.
- **Why:** `Sort-Object` gave `_a -c A a10 a9 b B`, the ordinal sort `-c A B _a a10 a9 b`; under `sv-SE`, `ä` sorted
  after `z`; `[IO.Directory]::GetFiles` was unsorted on ext4. **Verified.**
- **Source:** [Sort-Object](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/sort-object):
  "The sorted objects are delivered in the order they were received when the sort criteria are equal."

### P8. `$env:X = ''` sets an empty value; `$null` removes it
- **Rule:** Inside the 7.6 floor, assign `''` for "set but empty" and `$null` (or `Remove-Item Env:X`) to remove.
- **Why:** before 7.5 an empty string deleted the variable.
- **Source:** [about_Environment_Variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_environment_variables):
  "Beginning in PowerShell 7.5, you can set an environment variable to an empty string."

### P9. Temporary files and folders from the API, never from `$env:TEMP`
- **Rule:** `[IO.Path]::GetTempPath()` with `[guid]::NewGuid()`, `New-TemporaryFile`, or
  `[IO.Directory]::CreateTempSubdirectory('hyperdot-')` (available inside the floor). `GetTempFileName()` creates the file.
- **Why:** `$env:TEMP` and `$env:TMP` are empty on Linux, so `"$($env:Temp)\tmp1234.tmp"` becomes a relative junk path;
  four hex digits collide between parallel runs. **Verified.**
- **Source:** [Borrowing a built-in PowerShell command to create a temporary folder](https://devblogs.microsoft.com/powershell-community/borrowing-a-built-in-powershell-command-to-create-a-temporary-folder/)
  (do not): "Just create a number between 0 and 65535 with `Get-Random`".

### P10. Guard Windows-only cmdlets and APIs with `$IsWindows`
- **Rule:** Before `Get-Service`, CIM/WMI, COM, the registry or DPAPI, check `$IsWindows` and give Linux its own path or
  a clear `Stop-GodotCi` code.
- **Why:** `ProtectedData.Protect` loads on Linux and throws "Operation is not supported on this platform" when called,
  so a type check is not enough. **Verified.**
- **Source:** [Using Get-Service in PowerShell 7 vs. Windows PowerShell 5.1](https://devblogs.microsoft.com/powershell-community/using-get-service-in-powershell-7-vs-windows-powershell-5-1/):
  "in PowerShell 7, it's possible to read some additional properties that were not available in Windows PowerShell 5.1".

## Functions and parameters

### F1. A `[string]` parameter turns `$null` into `''`: test presence with `ContainsKey`
- **Rule:** `$PSBoundParameters.ContainsKey('Name')` for "was it given", `[string]::IsNullOrEmpty()` for the value.
- **Why:** `F` and `F -Value $null` both give `''`; defaults are not in `$PSBoundParameters`. **Verified.**
- **Source:** [Everything about null](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-null):
  "As soon as you set the type of the parameter as a `string`, the value can never be `$null`."

### F2. Switches: no default, decide on the value, forward with `-X:$X`
- **Why:** `-X:$false` or splatting makes a switch present but false, and a presence test turns it on.
- **Source:** [about_Functions_Advanced_Parameters](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters):
  "Always base the behavior controlled by the `[switch]` parameter on the _value_ of the parameter, not its _presence_."

### F3. Pipeline blocks run in the caller's scope; functions in a child scope
- **Rule:** Expect `ForEach-Object` and `Where-Object` blocks to overwrite the caller's variables (`$Matches`, `$_`);
  inside a function, assign run state with `$script:`.
- **Why:** a plain `$count = ...` in a helper makes a local and leaves the run's state unchanged.
- **Source:** [about_Scopes](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_scopes):
  "Items that you create or change in a child scope don't affect the parent scope, unless you explicitly specify the scope".

### F4. Splat: a hashtable for cmdlets, an array for native programs
- **Rule:** Build optional arguments in `@{}` or `@()` and splat them, instead of near-identical calls or strings.
- **Source:** [about_Splatting](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_splatting):
  "You can also use array splatting to pass values to native commands."

### F5. Round with `[Math]`, not an `[int]` cast
- **Rule:** `[Math]::Floor`, `::Ceiling`, `::Truncate` or `::Round(x, [MidpointRounding]::AwayFromZero)` for indices,
  frame counts and sizes.
- **Why:** `[int]2.5` is 2, `[int]3.5` is 4: casts round half to even. **Verified.**
- **Source:** [about_Arithmetic_Operators](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arithmetic_operators):
  "When the value is `.5`, it rounds to the nearest even integer."

### F6. No `$global:`; `$PSDefaultParameterValues` is shared
- **Rule:** Keep state in `$script:`. To change `$PSDefaultParameterValues` or a preference, assign a new value in a child
  scope and restore it; never index into it or `.Add()`.
- **Why:** `& { $PSDefaultParameterValues['ConvertTo-Json:Compress'] = $true }` changed the caller's dictionary, so every
  later `ConvertTo-Json` was compressed. **Verified.**
- **Source:** [How to Use $PSDefaultParameterValues](https://devblogs.microsoft.com/powershell-community/how-to-use-psdefaultparametervalues/):
  "the variable is subject to normal scoping rules" (true only for a fresh assignment).

### F7. Validation attributes in helpers, not on the `-Json` entry point
- **Rule:** Use `[ValidateSet]` and friends in helpers and tools; `hyperdot.ps1` keeps `[ArgumentCompletions]` plus its
  own check, so a bad value is reported as `invalid-arguments` in JSON.
- **Why:** a `[ValidateSet]` failure happens during binding, before the script's `trap` exists: stdout empty, exit 1,
  no JSON. **Verified.**
- **Source:** [Designing PowerShell For End Users](https://devblogs.microsoft.com/powershell-community/designing-powershell-for-end-users/):
  "adding guardrails to your tools using these methods … demonstrably increases the usability and adoption of your tools."
  (Right for functions, wrong for an entry point with a JSON error contract.)

## JSON and data

### J1. Every `ConvertTo-Json` gets a `-Depth`
- **Rule:** Pass `-Depth` above the deepest level the data can reach (up to 100).
- **Why:** `@{a=@{b=@{c=@{d=1}}}} | ConvertTo-Json -Compress` gives `{"a":{"b":{"c":"System.Collections.Hashtable"}}}`
  and a warning that does not stop the run and, in a child `pwsh`, lands on stdout (E7). **Verified, re-run.**
- **Source:** [ConvertTo-Json](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertto-json):
  "The default value is `2`. `ConvertTo-Json` emits a warning if the number of levels in an input object exceeds this number."

### J2. Arrays as `-InputObject @(...)` or `-AsArray`, never a bare pipe
- **Why:** `@(1) | ConvertTo-Json` gives `1`, `@() | ConvertTo-Json` gives nothing, `ConvertTo-Json -InputObject @()`
  gives `[]`. **Verified.**
- **Source:** [ConvertTo-Json](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertto-json):
  "Outputs the object in array brackets, even if the input is a single object."

### J3. `[ordered]` for every dictionary that reaches output
- **Rule:** Build JSON and CSV rows from `[ordered]@{}`; never cast a plain `@{}` held in a variable to `[pscustomobject]`.
- **Why:** `@{}` has no order, so fields move between runs (a plain hashtable came out `mid, alpha, zeta`).
- **Source:** [Everything about PSCustomObject](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-pscustomobject):
  "The biggest difference is that the order of the properties isn't preserved."

### J4. `ConvertFrom-Json` makes dates, unrolls arrays and returns `$null` for empty input
- **Rule:** Keep ISO timestamps as text with `-DateKind String` (inside the floor), or write them back with
  `.ToString('o', [cultureinfo]::InvariantCulture)`; `-NoEnumerate` when the top level is an array; treat an empty file
  as an error yourself.
- **Why:** `"2024-03-05T10:00:00Z"` came back as a `DateTime` that interpolates as `03/05/2024 10:00:00`; `'[]'` gave
  `$null`; `Get-Content -Raw` of an empty file gives `$null`, which passes through without complaint. **Verified.**
- **Source:** [ConvertFrom-Json](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/convertfrom-json):
  "This guarantees that JSON can be round-tripped via `ConvertTo-Json`." (on `-NoEnumerate`).

### J5. `-AsHashtable` gives an ordered, case-sensitive dictionary
- **Rule:** Read `-AsHashtable` documents with the key case the schema defines and validate the keys; `@{}` is
  case-insensitive, `[hashtable]::new()` and `-AsHashtable` results are not.
- **Why:** `('{"A":1}' | ConvertFrom-Json -AsHashtable)['a']` is empty, and the type is `OrderedHashtable`; on 7.2 the
  same call was case-insensitive and unordered, which the floor now rules out. **Verified.**
- **Source:** [about_Case-Sensitivity](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_case-sensitivity):
  "In PS v7.3, a change was made to treat JSON keys as case-sensitive when this parameter is specified."

### J6. CSV and tables take their columns from the first object
- **Rule:** `Select-Object -Property <full list>` before `Export-Csv`, `ConvertTo-Csv` or `Format-Table`.
- **Why:** a second object's `phone` was dropped without a warning because the first had `address`. **Verified.**
- **Source:** [Mastering the (steppable) pipeline](https://devblogs.microsoft.com/powershell-community/mastering-the-steppable-pipeline/):
  "a cmdlet written for one-at-a-time processing bases its output on the first object received from the pipeline."

### J7. Load XML with `XmlDocument.Load` from an absolute path
- **Rule:** `$x = [xml]::new(); $x.Load($fullPath)`, not `[xml](Get-Content $path)`.
- **Why:** `Get-Content` decodes before the parser sees `encoding=`: an ISO-8859-1 `café` came back as `caf�`.
  **Verified.**
- **Source:** [Update XML files using PowerShell](https://devblogs.microsoft.com/powershell-community/update-xml-files-using-powershell/)
  (the anti-pattern): `$xml = [xml](Get-Content $path)`.

## Concurrency

### X1. New runspaces, modules and child processes start without your settings
- **Rule:** Every `ForEach-Object -Parallel` block, `Start-ThreadJob`/`Start-Job` script block, `.psm1` module and child
  `pwsh` sets `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'` itself; pass data with `$using:` or
  `-ArgumentList`; dot-source the lib files it needs.
- **Why:** inside `-Parallel`, `$ErrorActionPreference` was `Continue` and an unset variable read as empty (re-run);
  callers' functions are "not found"; a module function sees the global preference, not its caller's. The kit's lib
  files are dot-sourced into one scope, so this matters for the thread jobs in `tests/Test-PrComment.ps1` and
  `tests/Test-TrelloSync.ps1` and for any future module. **Verified, re-run.**
- **Source:** [about_Scopes](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_scopes):
  "For any script or command that executes out of session, you need the `Using:` scope modifier". [On Preferences and Scopes](https://devblogs.microsoft.com/powershell-community/how-to-have-more-control-of-preferences-in-functions-and-the-role-of-modules-on-inheritance/):
  "what happens in a module stays in the module."

### X2. Share only thread-safe objects; expect any order
- **Rule:** Return results from the block or collect them in `System.Collections.Concurrent` types; set
  `-ThrottleLimit` on purpose (default 5); do not parse ordered output.
- **Source:** [ForEach-Object](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/foreach-object):
  "If you need to modify the object state then you must use thread safe objects".

### X3. Jobs: check `Wait-Job -Timeout`'s result, wrap `Receive-Job`, clean up in `finally`
- **Why:** `Wait-Job -Timeout 1` on a 5 s job returned `$null` with the job still running; `Receive-Job` rethrew a failed
  job's error under `Stop`; a forgotten job keeps a stand-in server and its port alive. **Verified.**
- **Source:** [Parallel execution](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/parallel-execution):
  "`Start-ThreadJob` ... uses PowerShell runspaces to create and manage thread-based jobs."

## Performance

### R1. Collect a loop's output or use `List[T]`; no array `+=` in loops
- **Rule:** `$x = @(foreach (...) { ... })` or `[System.Collections.Generic.List[object]]::new()` with `.Add()`.
- **Why:** 7.5 made `+=` much cheaper, but on 7.6 20,000 adds still took 1,185 ms against 10 ms for a `List` and 7 ms
  for loop assignment. Short failure lists are fine. **Verified.**
- **Source:** [Script authoring considerations](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations):
  "In PowerShell 7.5, array addition was optimized and no longer creates a new array for each operation."

### R2. Look up by key; stop at the first match
- **Rule:** Index a collection once into a hashtable instead of `Where-Object` inside a loop; `.Where({ ... }, 'First')`
  for "is there any".
- **Source:** [Script authoring considerations](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations):
  "Looking up keys in a hash table is much faster than filtering a collection by property values."

### R3. `$null =` rather than `| Out-Null`; `[pscustomobject]` rather than `New-Object` and `Add-Member` in loops
- **Why:** 100,000 iterations: `| Out-Null` 450 ms, `$null =` and `[void]` 5 ms. **Verified.** The docs measured
  `New-Object` at about 7 times `[pscustomobject]`.
- **Source:** [Script authoring considerations](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations):
  "calling `Out-Null` in a large loop can be significantly slower".

### R4. One pipeline per stream, not one per item
- **Rule:** Pipe a whole collection once into `Export-Csv`, `Set-Content` or `ConvertTo-Json`; when output branches, use
  a steppable pipeline (`{ Export-Csv -Path $f }.GetSteppablePipeline()` with `Begin($true)`, `Process($_)`, `End()`).
- **Why:** 3,000 rows: per-item `Export-Csv -Append` 4,613 ms, steppable 47 ms, one pipeline 21 ms. **Verified.**
- **Source:** [Mastering the (steppable) pipeline](https://devblogs.microsoft.com/powershell-community/mastering-the-steppable-pipeline/):
  "Wrapping a cmdlet pipeline into another (`ForEach-Object`) pipeline is very expensive".

### R5. Strings with `-join` or `StringBuilder`; hot loops in C#
- **Rule:** Collect pieces and `-join` them, or use `[Text.StringBuilder]`; read large logs with
  `[IO.File]::ReadLines($absolutePath)`; move per-pixel or per-sample loops into C# compiled with `Add-Type` (as
  `Sfxr.cs`, `Heatmap.cs` and `Palette.cs` are), and the loop inside a function rather than the function inside a loop.
- **Why:** 20,000 string `+=` took 3,434 ms, `StringBuilder` 16 ms, `-join` 34 ms. `Add-Type` with changed source for a
  type already loaded fails ("already exists"), so a long-lived session keeps the old code. **Verified.**
- **Source:** [Script authoring considerations](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations):
  "the `-join` operator is the fastest, followed by the `[StringBuilder]` class." [Measuring average download time](https://devblogs.microsoft.com/powershell-community/measuring-download-time/):
  "We are calling the OS API directly!"

### R6. `Get-Content -Tail` for the end of a file, `-Raw` for all of it
- **Why:** on 500,000 lines, `| Select-Object -Last 1` took 3,053 ms and `-Tail 1` 5 ms; plain `Get-Content` 4,657 ms,
  `-Raw` 21 ms. **Verified.**
- **Source:** [Reading a text file bottom up](https://devblogs.microsoft.com/powershell-community/reading-a-text-file-bottom-up/)
  (outdated): "Windows, .NET, and PowerShell do not provide a way to read the file in reverse."

### R7. Time with a `Stopwatch`, not `Measure-Command`
- **Why:** `Measure-Command` runs the block in the current scope and drops its output: `$x = 0; Measure-Command { $x = 5 }`
  left `$x` at 5. **Verified.**
- **Source:** [Measuring script execution time](https://devblogs.microsoft.com/powershell-community/measuring-script-execution-time/):
  "`Measure-Command` runs the script block in the current scope".

## Secrets

### K1. CI secrets live in the runner's environment, go in headers, never in URLs
- **Rule:** Read secrets from environment variables set from repository secrets, never echo them, send them in headers;
  on a developer machine use `Microsoft.PowerShell.SecretManagement`. Never `ConvertFrom-SecureString`,
  `Export-Clixml` or DPAPI as protection on Linux.
- **Why:** on Linux `ConvertFrom-SecureString` returned the UTF-16 plaintext in hex; a failed `Invoke-RestMethod` keeps
  the full URI, query string included, in `$_.TargetObject`. **Verified.**
- **Source:** [How to use the Secret modules](https://devblogs.microsoft.com/powershell-community/how-to-use-the-secret-modules/):
  "So stop using plain text secrets in your PowerShell scripts and use the secrets modules."

### K2. `RandomNumberGenerator` for anything secret
- **Rule:** `[Security.Cryptography.RandomNumberGenerator]::GetInt32(n)` or `::GetBytes(n)`; `Get-Random` only for test data.
- **Source:** [Porting System.Web.Security.Membership.GeneratePassword() to PowerShell](https://devblogs.microsoft.com/powershell-community/porting-system-web-security-membership-generatepassword-to-powershell/)
  (uses the obsolete `RNGCryptoServiceProvider`). **Verified** (both calls work on 7.6).

## Testing and tooling

### T1. Test on the floor version, under other cultures and with hostile paths
- **Rule:** Run self-tests on 7.6 (the runners' version today), part of them under `de-DE` and `tr-TR`, and from a
  folder whose path holds a space, `[ ]` and a non-ASCII character.
- **Why:** these catch C1, C3, P1 and N2, which an English Linux runner never shows. `Test-Plan.ps1`,
  `Test-Audio.ps1` and `Test-BenchHotspots.ps1` already run under other cultures, `Test-InstallAddon.ps1` with brackets.
- **Source:** [PS101: formatting, aliases, providers, comparison](https://learn.microsoft.com/powershell/scripting/learn/ps101/05-formatting-aliases-providers-comparison):
  "you can encounter unforeseen problems, such as failing the _Turkey Test_."

### T2. Lint with PSScriptAnalyzer, pinned and curated
- **Rule:** Every tracked script passes `Invoke-ScriptAnalyzer` 1.25.0 with
  [PSScriptAnalyzerSettings.psd1](../ci/godot/PSScriptAnalyzerSettings.psd1) (see "How this is checked").
- **Source:** [Everything about null](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-null):
  "The PSScriptAnalyzer module has a rule that checks for this issue called `PSPossibleIncorrectComparisonWithNull`."
  **Verified** (run over all 163 scripts).

### T3. The floor is 7.6; use what it allows
- **Rule:** Write for 7.6 and test on it; see "Version floor" for what that settles.
- **Source:** [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle).

## Advice that does not hold here

From the sources, outdated or wrong for 7.6 on Linux under strict mode:

| Where | Advice | Instead |
|---|---|---|
| [Everything about PSCustomObject](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-pscustomobject) | "check for that property to have a value. `if( $null -ne $myObject.ID )`" | Throws under strict mode: `.PSObject.Properties['ID']` (S2) |
| [Everything about null](https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-null) | "Use the automatic variable `$PSBoundParameters.Value` instead." | Throws when not passed: `.ContainsKey('Value')` (S2, F1) |
| [about_Arrays](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_arrays) | Every scalar has `Count` | Not under strict mode: `@($x).Count` (S1) |
| [Mastering the (steppable) pipeline](https://devblogs.microsoft.com/powershell-community/mastering-the-steppable-pipeline/) | Same-file `Get-Content \| Set-Content` "causes the following error" | Silent truncation on Linux (S12) |
| [Reading a text file bottom up](https://devblogs.microsoft.com/powershell-community/reading-a-text-file-bottom-up/) | No way to read a file from the end | `Get-Content -Tail` (R6) |
| [Crescendo output handler](https://devblogs.microsoft.com/powershell-community/a-closer-look-at-the-parsing-code-of-a-crescendo-output-handler/) | `` -split "`r`n`r`n" `` | `'\r?\n'` (C6) |
| [Converting string output to objects](https://devblogs.microsoft.com/powershell-community/converting-string-output-to-objects/) | Skip a fixed number of header lines per OS | Anchor on the header text (N9) |
| [How to Use $PSDefaultParameterValues](https://devblogs.microsoft.com/powershell-community/how-to-use-psdefaultparametervalues/) | Changing it in a script "does not affect the session" | True only for a fresh assignment (F6) |
| [Borrowing a built-in command (temp folder)](https://devblogs.microsoft.com/powershell-community/borrowing-a-built-in-powershell-command-to-create-a-temporary-folder/) | `"$($ENV:Temp)\tmpXXXX.tmp"` | `GetTempPath()` with a GUID (P9) |
| [Getting Yesterday's Date](https://devblogs.microsoft.com/powershell-community/getting-yesterdays-date/) | `ToString() -replace '/','-'` for file names | Invariant `yyyy-MM-dd` (C1) |
| [Convert … excel sheet to JSON](https://devblogs.microsoft.com/powershell-community/convert-specific-table-of-excel-sheet-to-json/) | `Out-File -Encoding ASCII`, `$results +=`, no `-Depth`, `GetFullPath(relative)` | C5, R1, J1, J2, P4 |
| [Update XML files](https://devblogs.microsoft.com/powershell-community/update-xml-files-using-powershell/) | `[xml](Get-Content $path)` | `XmlDocument.Load` (J7) |
| [Encrypting secrets locally](https://devblogs.microsoft.com/powershell-community/encrypting-secrets-locally/) | DPAPI "tested under version 5 & 7" | Windows only; throws on Linux (P10, K1) |
| [Measuring average download time](https://devblogs.microsoft.com/powershell-community/measuring-download-time/) | `HttpWebRequest`; `$Host.Version` for the edition | Obsolete since .NET 6: `Invoke-WebRequest` or `HttpClient`; `$PSVersionTable.PSVersion` |
| [Porting … GeneratePassword](https://devblogs.microsoft.com/powershell-community/porting-system-web-security-membership-generatepassword-to-powershell/) | `RNGCryptoServiceProvider`, `$global:` state, `LoadWithPartialName` | K2, F6; `LoadWithPartialName` is obsolete |
| [On Preferences and Scopes](https://devblogs.microsoft.com/powershell-community/how-to-have-more-control-of-preferences-in-functions-and-the-role-of-modules-on-inheritance/) | Web cmdlets' `-Verbose` omits the URI, hence a proxy | 7.6 prints the URI without its query |
| [Lightning-fast provisioning of Git](https://devblogs.microsoft.com/powershell-community/lightning-fast-and-easy-provisioning-of-git-with-ssh-key-authentication-on-windows/) | `iwr … \| iex` | Never run downloaded code through `Invoke-Expression` (N1) |
| [Script authoring considerations](https://learn.microsoft.com/powershell/scripting/dev-cross-plat/performance/script-authoring-considerations), [about_Parsing](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_parsing), [about_Redirection](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_redirection) | Workarounds for `+=` cost, legacy argument passing and text-only native pipes | Needed before 7.5, 7.3 and 7.4; the 7.6 floor settles them (R1, N1, N5) |


## How this is checked

| Check | Lessons | Run by |
|---|---|---|
| PSScriptAnalyzer 1.25.0, [settings](../ci/godot/PSScriptAnalyzerSettings.psd1), every tracked `.ps1` | S6 (`PSPossibleIncorrectComparisonWithNull`), N1 (`PSAvoidUsingInvokeExpression`), P5 on Windows (`PSAvoidUsingCmdletAliases`), F2 (`PSAvoidDefaultValueSwitchParameter`), F6 (`PSAvoidGlobalVars`), N10 for cmdlets (`PSAvoidOverwritingBuiltInCmdlets`), S5 in part (`PSUseDeclaredVarsMoreThanAssignments`), empty `catch`, `if ($a = 1)`, `>` for `-gt`, automatic variables, misleading backticks, trailing whitespace | the lint job of `.github/workflows/self-test.yml`, failing on any finding |
| [Test-PowerShellPatterns.ps1](../tests/Test-PowerShellPatterns.ps1), every tracked `.ps1`, read from the syntax tree | E1 (`pipeline-continue`), S6 (`null-on-right`), N1 (`invoke-expression`), P3 (`path-combine`), S2 and F1 (`boundparams-dot`), E3 for assignments (`lowered-erroraction`), P4 for literal paths (`relative-dotnet-path`), S11 (`strictmode-latest`), P5 on Linux (`windows-alias`), S12 (`same-file-pipeline`) | the same lint job; each check proven on `tests/powershell-patterns-fixture/` |
| `tests/Test-LibNames.ps1` | N10 for aliases and cmdlets in `ci/godot` | the lint job |
| Self-tests under other cultures and odd paths | C1, P1 (in part) | `Test-Plan.ps1`, `Test-Audio.ps1`, `Test-BenchHotspots.ps1`, `Test-InstallAddon.ps1` |
| Review | everything else, notably E2, E7, J1, J2, C1, N2, N3, P1 and S1, which have uses in the repository today and so cannot be hard checks | the person or agent changing the code |

The pattern test holds only what has no use left in the repository; patterns that still have uses (for example
`ConvertTo-Json` without `-Depth`, `Start-Process -ArgumentList`, `-Path` where `-LiteralPath` belongs) are left to a
review of every script, after which they can join it.

## Version floor

**Decision (2026-10-26): the floor is PowerShell 7.6**, the current LTS release, in every `#Requires` and in
[AGENTS.md](../AGENTS.md) ("Targets").

- **Support.** 7.2 (LTS) ended on 8 November 2024; 7.4 (LTS) and 7.5 end on 10 November 2026; 7.6 (LTS, released
  18 March 2026) is supported until 14 November 2028 ([support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle):
  "PowerShell 7.6 (LTS) | 18-Mar-2026 | 14-Nov-2028"). PowerShell's
  [tools/metadata.json](https://github.com/PowerShell/PowerShell/blob/master/tools/metadata.json) names
  `"LTSReleaseTag": ["v7.4.22", "v7.6.9"]` and `"StableReleaseTag": "v7.6.9"`.
- **Runners.** GitHub's images already ship 7.6 (actions/runner-images: Ubuntu 22.04 and 24.04 7.6.6, Windows Server
  2022 7.6.8, Windows Server 2025 7.6.7, macOS 15 arm64 7.6.5), as does the container these lessons were run in (7.6.6).
  The GitLab template's .NET 8 SDK image carries 7.4, so its `before_script` unpacks 7.6.9.
- **What 7.6 settles**, compared with the 7.2 floor before it: native arguments keep empty strings and quotes (7.3, N1);
  `$PSNativeCommandUseErrorActionPreference` exists (7.4, E2, N7); native bytes survive `>` and `|` (7.4, N5);
  `-AsHashtable` is ordered and case-sensitive everywhere (7.3, J5); `ConvertTo-Json -Depth` goes to 100 (7.3, J1);
  `+=` no longer copies the array each time (7.5, R1); `$env:X = ''` keeps an empty variable (7.5, P8);
  `ConvertFrom-Json -DateKind` (7.5, J4); `[IO.Directory]::CreateTempSubdirectory` (P9). A local Windows user now runs the
  same behaviour as CI.
- **Not settled.** PSScriptAnalyzer's compatibility rules ship no profile newer than 7.0, so nothing checks that a
  script avoids APIs newer than the floor; the floor is the version CI runs.

## Sources

Lessons from the Microsoft PowerShell documentation ([MicrosoftDocs/PowerShell-Docs](https://github.com/MicrosoftDocs/PowerShell-Docs)
at commit `a3de8f2`, 24 September 2026; reference pages for 7.5), © Microsoft, licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), its code samples MIT; and from the
[PowerShell Community blog](https://devblogs.microsoft.com/powershell-community/) (all 49 posts, 2021 to 2024, read
26 October 2026), © Microsoft and the posts' authors, which states no open licence: only short quotes, linked to their
posts, are used. The rules and explanations are this project's wording.
