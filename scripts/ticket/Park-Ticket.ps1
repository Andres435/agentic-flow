#Requires -Version 7
<#
.SYNOPSIS
    Record a ticket that stops before /complete-task (ADO "More Info Needed", or closed early
    by ADO): close the open work span at now, write a ledger row, and run the park gate.

.DESCRIPTION
    A ticket that never reaches /complete-task has no close stamp, so its open span keeps
    growing and its hours absorb the idle gap. Run this once, when the ticket parks. It needs
    no scorecard, no story points, no verify receipt and no review stamp.

    Steps:
      1 resolve   manifest found, workType known, not already closed through /complete-task
      2 span      the open span (original, reopen, or resume) is closed at now and written to
                  spans[]; parkedAtUtc, parkedState and parkedOutcome are stamped. A repeat
                  park keeps the first stamp (a retry after a failed later step).
      3 hours     Get-SessionHours.ps1 -Json over the closed spans; parkedHours is stored
      4 ledger    Update-TicketLedger.ps1 -Outcome (no E/C/$tok, no points; a later real close
                  replaces the row)
      5 gate      Assert-TicketArtifacts.ps1 -Phase park

    /start-ticket resumes a parked ticket with Resume-Ticket.ps1, which opens a new span so
    the gap stays excluded. The final /complete-task close sums every span.

    -WhatIf lists the steps and writes nothing.

.PARAMETER Ticket
    Work item, with or without the WI prefix.

.PARAMETER Outcome
    more-info (ADO state More Info Needed) or closed-by-ado (closed early by ADO).

.PARAMETER State
    The ADO state text to record as parkedState. Defaults to "More Info Needed" or "Closed".

.PARAMETER Pr
    PR number or URL, if one exists.

.PARAMETER Root
    Override the tmo-agentic repo root (tests).

.EXAMPLE
    .\scripts\ticket\Park-Ticket.ps1 -Ticket WI22758 -Outcome more-info
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Ticket,
    [Parameter(Mandatory)][ValidateSet('more-info', 'closed-by-ado')][string]$Outcome,
    [string]$State,
    [string]$Pr,
    [string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Join-Path $PSScriptRoot 'lib') 'ManifestFields.ps1')

$Key = Get-TicketKeyFromRaw -Ticket $Ticket
$RepoRoot = if ($Root) { $Root } else { Get-CursorRepoRoot -FromScriptRoot $PSScriptRoot }
$manifestPath = Get-TicketManifestFile -RepoRoot $RepoRoot -TicketKey $Key
$rootArgs = if ($Root) { @{ Root = $Root } } else { @{} }
if (-not $State) { $State = if ($Outcome -eq 'more-info') { 'More Info Needed' } else { 'Closed' } }

$stepNames = @('resolve', 'span', 'hours', 'ledger', 'gate')

function Stop-Park {
    param([int]$N, [string]$Fix, [string]$Detail)
    Write-Output "[FAIL] park step $N ($($stepNames[$N - 1])): $Fix"
    foreach ($line in @(($Detail -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 8)) {
        Write-Output "       $($line.Trim())"
    }
    exit 1
}

function Invoke-ParkScript {
    param([int]$N, [string]$Script, [hashtable]$Splat, [string]$Fix)
    $global:LASTEXITCODE = 0
    try { $out = (& (Join-Path $PSScriptRoot $Script) @Splat *>&1 | Out-String) }
    catch { Stop-Park -N $N -Fix $Fix -Detail $_.Exception.Message }
    if ($global:LASTEXITCODE -ne 0) { Stop-Park -N $N -Fix $Fix -Detail $out }
    return $out
}

function Read-Manifest { Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json }

function Get-Field {
    param($Obj, [string]$Name)
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

# ---- 1 resolve (read only) -----------------------------------------------------
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Stop-Park -N 1 -Fix "no manifest at $manifestPath; run /start-ticket first, or pass the right -Ticket/-Root" -Detail ''
}
$manifest = Read-Manifest
$workType = [string](Get-Field $manifest 'workType')
if ($workType -notin @('bug', 'feature', 'spike', 'refactor')) {
    Stop-Park -N 1 -Fix "manifest workType '$workType' is not bug|feature|spike|refactor; fix it, then re-run" -Detail ''
}
$mode = [string](Get-Field $manifest 'mode')
$alreadyParked = [bool](Get-Field $manifest 'parkedAtUtc')
if (-not $alreadyParked -and -not (Test-TicketManifestOpen $manifest)) {
    Stop-Park -N 1 -Fix "$Key is already closed through /complete-task (completedAtUtc set); nothing to park" -Detail ''
}
if (-not (Get-Field $manifest 'startedAtUtc')) {
    Stop-Park -N 1 -Fix 'manifest has no startedAtUtc; the span cannot be closed' -Detail ''
}

if (-not $PSCmdlet.ShouldProcess($Key, "park ticket ($Outcome)")) {
    Write-Output "[WhatIf] $Key ($workType, $mode): resolve passed; the rest would run in order, writing nothing now:"
    Write-Output '[WhatIf] park step 2 (span): close the open span at now; parkedAtUtc, parkedState, parkedOutcome'
    Write-Output '[WhatIf] park step 3 (hours): Get-SessionHours.ps1 -Json; parkedHours'
    Write-Output "[WhatIf] park step 4 (ledger): Update-TicketLedger.ps1 -Type $workType -Outcome $Outcome (no scorecard, no points)"
    Write-Output '[WhatIf] park step 5 (gate): Assert-TicketArtifacts.ps1 -Phase park'
    exit 0
}

# ---- 2 span -------------------------------------------------------------------
$now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
try {
    if ($alreadyParked) {
        Write-Output "[OK] park step 2 (span): already parked at $(Get-Field $manifest 'parkedAtUtc'); kept"
    }
    else {
        $spans = New-Object System.Collections.Generic.List[object]
        foreach ($s in @(Get-Field $manifest 'spans')) {
            if (-not $s) { continue }
            $spans.Add([pscustomobject]@{
                kind         = [string](Get-Field $s 'kind')
                startedAtUtc = Get-Field $s 'startedAtUtc'
                endedAtUtc   = Get-Field $s 'endedAtUtc'
            })
        }
        $open = @($spans | Where-Object { $_.startedAtUtc -and -not $_.endedAtUtc })
        if ($open.Count -gt 0) {
            foreach ($o in $open) { $o.endedAtUtc = $now }
        }
        else {
            $hasKind = { param($k) @($spans | Where-Object { $_.kind -eq $k }).Count -gt 0 }
            $reopened = [string](Get-Field $manifest 'reopenedAtUtc')
            if ($reopened -and -not (Get-Field $manifest 'reclosedAtUtc') -and -not (& $hasKind 'reopen')) {
                $spans.Add([pscustomobject]@{ kind = 'reopen'; startedAtUtc = ConvertTo-IsoUtcText (Get-Field $manifest 'reopenedAtUtc'); endedAtUtc = $now })
            }
            elseif (-not (& $hasKind 'original') -and -not (Get-Field $manifest 'completedAtUtc')) {
                $spans.Add([pscustomobject]@{ kind = 'original'; startedAtUtc = ConvertTo-IsoUtcText (Get-Field $manifest 'startedAtUtc'); endedAtUtc = $now })
            }
            else {
                Stop-Park -N 2 -Fix 'no open span to close; the spans on the manifest are already all closed' -Detail ''
            }
        }
        Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{
            spans         = $spans.ToArray()
            parkedAtUtc   = $now
            parkedState   = $State
            parkedOutcome = $Outcome
        }
        Write-Output "[OK] park step 2 (span): open span closed, parkedAtUtc = $now ($State)"
    }
}
catch { Stop-Park -N 2 -Fix 'could not write the park stamp to the manifest' -Detail $_.Exception.Message }

# ---- 3 hours ------------------------------------------------------------------
$hoursOut = Invoke-ParkScript -N 3 -Script 'Get-SessionHours.ps1' `
    -Splat (@{ Ticket = $Key; Json = $true } + $rootArgs) `
    -Fix 'session hours could not be computed; check startedAtUtc and the spans on the manifest'
try { $session = $hoursOut | ConvertFrom-Json }
catch { Stop-Park -N 3 -Fix 'Get-SessionHours.ps1 did not return JSON' -Detail $hoursOut }
$hours = [double]$session.hours
$hoursText = $hours.ToString([cultureinfo]::InvariantCulture)
try { Merge-TicketManifestFields -ManifestPath $manifestPath -Patch @{ parkedHours = $hours } }
catch { Stop-Park -N 3 -Fix 'could not write parkedHours to the manifest' -Detail $_.Exception.Message }
Write-Output "[OK] park step 3 (hours): $hoursText h (idle gap excluded)"

# ---- 4 ledger -----------------------------------------------------------------
$ledger = @{ Ticket = $Key; Type = $workType; Hours = $hoursText; Outcome = $Outcome }
if ($mode -in @('branch', 'worktree', 'investigate')) { $ledger.Mode = $mode }
if ($Pr) { $ledger.Pr = $Pr }
$null = Invoke-ParkScript -N 4 -Script 'Update-TicketLedger.ps1' -Splat ($ledger + $rootArgs) `
    -Fix 'the ledger row was not written; fix the error above and re-run Park-Ticket.ps1'
Write-Output "[OK] park step 4 (ledger): $Outcome row written for $Key"

# ---- 5 gate -------------------------------------------------------------------
$null = Invoke-ParkScript -N 5 -Script 'Assert-TicketArtifacts.ps1' `
    -Splat (@{ Ticket = $Key; Phase = 'park' } + $rootArgs) `
    -Fix 'the park gate fails; fix what is listed and re-run'

Write-Output "[PASS] $Key parked ($State): $hoursText h, ledger row written, park gate passed. Resume with Resume-Ticket.ps1."
exit 0
