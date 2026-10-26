@{
    # Information too: it adds PSPossibleIncorrectUsageOfAssignmentOperator (`if ($a = 1)`), PSAvoidTrailingWhitespace,
    # PSUseOutputTypeCorrectly and PSProvideCommentHelp, all clean today. The lint job of self-test.yml scans every tracked
    # .ps1 with this file and fails on any finding; docs/powershell.md says which lessons it enforces.
    Severity     = @('Error', 'Warning', 'Information')
    ExcludeRules = @(
        # A CLI talks to the console on purpose: logs go through Write-Host / Write-CiLog (stderr under -Json).
        'PSAvoidUsingWriteHost',
        # Internal helpers, not cmdlets: no -WhatIf, and names read better as they are.
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseSingularNouns',
        # Blind to parameters read in nested script blocks or the script's own functions (Deck.ps1, Setup.ps1): 16 of 16 false.
        'PSReviewUnusedParameter',
        # House style (`Join-Path $a $b`, the kit's own helpers): 491 findings, none a bug.
        'PSAvoidUsingPositionalParameters',
        # The kit needs PowerShell 7.2+, which reads UTF-8 without a BOM; the rule is for Windows PowerShell 5.1.
        'PSUseBOMForUnicodeEncodedFile',
        # 1.25.0 flags the param() variables of a Start-ThreadJob -ArgumentList block, the right way in (5 of 5 false).
        'PSUseUsingScopeModifierInNewRunspaces'
    )
    # Left off (opt-in rules), measured on every tracked .ps1 with 1.25.0:
    # - PSUseCompatibleSyntax/Commands/Types: no profile newer than 7.0 ships; 5 findings, all false (guarded `kill`, `ps`).
    # - PSUseCorrectCasing: 76 findings, all `Where-Object X -eq Y`; it also throws NullReferenceException on some files.
    # - Formatting (indentation, whitespace, braces, alignment, long lines): about 4,200 findings against the house layout.
    # - PSUseConstrainedLanguageMode: the kit never runs in Constrained Language Mode.
}
