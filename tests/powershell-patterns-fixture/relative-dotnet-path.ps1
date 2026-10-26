# Deliberately bad: tests/Test-PowerShellPatterns.ps1 must flag every line marked "flagged" as relative-dotnet-path.
$text = [System.IO.File]::ReadAllText('results/summary.json')   # flagged
[IO.File]::WriteAllText("out/$($text.Length).txt", $text)   # flagged
$full = [IO.Path]::GetFullPath('build')   # flagged
$writer = [IO.StreamWriter]::new('log.txt')   # flagged
if ([IO.Directory]::Exists('tmp')) { 'there' }   # flagged
