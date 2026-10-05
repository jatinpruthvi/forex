# compile_all.ps1 - Stage 0 of docs/EA_VALIDATION_PLAYBOOK.md, scripted.
#
# Compiles, with MetaEditor's command line:
#   * the 65 delivered EAs      (MQL5\Experts\additionalEAs\*.mq5)
#   * the portfolio trader      (MQL5\Experts\...\AllEnginesEA.mq5)
#   * the portfolio tracker     (MQL5\Experts\...\PortfolioEA.mq5)
# and prints one line per file plus a total.  Exit code 1 when anything failed,
# so it can gate the tester sweep that follows.
#
# Usage (PowerShell):
#   .\compile_all.ps1 -Mql5 "C:\Users\you\AppData\Roaming\MetaQuotes\Terminal\<ID>\MQL5"
#   .\compile_all.ps1 -Mql5 "..." -MetaEditor "D:\MT5\metaeditor64.exe"
#
# Nothing here is required to run the EAs - it is the compile check the Linux
# audit cannot do, and the first step you should run on Windows.

param(
    [Parameter(Mandatory = $true)][string]$Mql5,
    [string]$MetaEditor = ""
)

$ErrorActionPreference = "Stop"

# --- locate metaeditor64.exe -------------------------------------------------
if ([string]::IsNullOrWhiteSpace($MetaEditor)) {
    $candidates = @(
        "C:\Program Files\MetaTrader 5\metaeditor64.exe",
        "C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe"
    ) + @(Get-ChildItem "C:\Program Files" -Filter "metaeditor64.exe" -Recurse -ErrorAction SilentlyContinue |
          Select-Object -ExpandProperty FullName) +
        @(Get-ChildItem "$env:LOCALAPPDATA\Programs" -Filter "metaeditor64.exe" -Recurse -ErrorAction SilentlyContinue |
          Select-Object -ExpandProperty FullName)
    $MetaEditor = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $MetaEditor -or -not (Test-Path $MetaEditor)) {
    throw "metaeditor64.exe not found - pass -MetaEditor `"C:\...\metaeditor64.exe`""
}
Write-Host "MetaEditor : $MetaEditor"
Write-Host "MQL5 root  : $Mql5"
Write-Host ""

# --- what to compile --------------------------------------------------------
$targets = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$expected = @()
$scriptGaps = @()

$additional = Join-Path $Mql5 "Experts\additionalEAs"
if (Test-Path $additional) {
    Get-ChildItem "$additional\*.mq5" | ForEach-Object { $targets.Add($_) }
} else {
    $expected += "MQL5\Experts\additionalEAs\*.mq5          (the 65 delivered EAs)"
}

foreach ($name in @("AllEnginesEA.mq5", "PortfolioEA.mq5")) {
    $hit = Get-ChildItem (Join-Path $Mql5 "Experts") -Filter $name -Recurse -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { $targets.Add($hit) }
    else      { $expected += "MQL5\Experts\...\$name" }
}

# Scripts (optional but recommended): the calendar exporter fills the file the
# six fail-closed news engines need; the launcher/preflight are the harness tools.
foreach ($name in @("ExportRedNews.mq5", "PortfolioLauncher.mq5", "UniversePreflight.mq5")) {
    $hit = Get-ChildItem (Join-Path $Mql5 "Scripts") -Filter $name -ErrorAction SilentlyContinue |
           Select-Object -First 1
    if ($hit) { $targets.Add($hit) }
    else      { $scriptGaps += "MQL5\Scripts\$name" }
}

if ($targets.Count -eq 0) {
    Write-Host "Nothing to compile.  Copy the files first:"
    $expected | ForEach-Object { Write-Host "  - $_" }
    exit 2
}
if ($expected.Count -gt 0) {
    Write-Host "Not found yet (will be skipped):"
    $expected | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
}
if ($scriptGaps.Count -gt 0) {
    Write-Host "Scripts not copied (optional - only needed for the calendar export / launcher):"
    $scriptGaps | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
}

# --- compile ----------------------------------------------------------------
$totalErrors = 0
$totalWarnings = 0
$failed = @()

foreach ($t in $targets) {
    $log = [System.IO.Path]::ChangeExtension($t.FullName, ".log")
    if (Test-Path $log) { Remove-Item $log -Force }
    & $MetaEditor /compile:"$($t.FullName)" /log 2>$null | Out-Null

    $errors = 0; $warnings = 0
    if (Test-Path $log) {
        # MetaEditor writes the log as UTF-16; fall back to the default encoding.
        $text = Get-Content $log -Raw -Encoding Unicode -ErrorAction SilentlyContinue
        if (-not $text) { $text = Get-Content $log -Raw -ErrorAction SilentlyContinue }
        if (-not $text) { $text = "" }

        # The exact wording of MetaEditor's command-line log is not verified anywhere
        # (this environment has no MetaEditor), so do not hinge success on one exact
        # string.  Match case-insensitively and require positive evidence that the
        # compiler actually ran - the log names the source file, or carries a
        # result/summary line, or reports an explicit error count.
        $errors   = ([regex]::Matches($text, "(?i):\s*error")).Count
        $warnings = ([regex]::Matches($text, "(?i):\s*warning")).Count
        $ran = ($text -match [regex]::Escape($t.Name)) -or
               ($text -match "(?i)information:\s*result") -or
               ($text -match "(?i)\b\d+\s+errors?\b") -or
               ($text -match "(?i)errors?:\s*0")
        if (-not $ran) { $errors = 1 }   # nothing in the log proves a compile happened
    } else {
        $errors = 1                       # no log = compile did not run
    }

    $totalErrors += $errors
    $totalWarnings += $warnings
    if ($errors -gt 0) { $failed += $t.FullName }
    Write-Host ("{0,-46} errors {1,-3} warnings {2}" -f $t.Name, $errors, $warnings)
}

Write-Host ""
Write-Host ("TOTAL  compiled {0} file(s)   errors {1}   warnings {2}" -f $targets.Count, $totalErrors, $totalWarnings)

if ($totalErrors -gt 0) {
    Write-Host ""
    Write-Host "First errors (send these to the maintainer, together with the .log files):"
    $targets | ForEach-Object {
        $log = [System.IO.Path]::ChangeExtension($_.FullName, ".log")
        if (Test-Path $log) {
            Select-String -Path $log -Pattern ": error" -Encoding Unicode |
                Select-Object -First 3 | ForEach-Object { Write-Host ("  [" + $_.Filename + "] " + $_.Line.Trim()) }
        }
    }
    Write-Host ""
    Write-Host "Rule: compile errors are fixed in MQL5_Master\Include (engine) or"
    Write-Host "portfolio-EA\gen_portfolio_ea.py (host) / portfolio-EA\src (tracker) -"
    Write-Host "never in the generated build\ file, which the generator overwrites."
    exit 1
}

if ($totalWarnings -gt 0) {
    Write-Host ""
    Write-Host "No errors.  Warnings are usually conversion/sign hints - send them along and"
    Write-Host "they will be triaged, but they do not block the tester sweep."
}
exit 0
